# corona shiny

# Load libraries ----------------------------------------------------------
library(tidyverse)
library(httr)
library(jsonlite)
library(RcppRoll)
library(shiny)


# Read in data ----

# country code from https://datahub.io/core/country-codes
# country pop from world bank: https://data.worldbank.org/indicator/SP.POP.TOTL
# corona api https://documenter.getpostman.com/view/10808728/SzS8rjbc#7934d316-f751-4914-9909-39f1901caeb8

countries_pop <- read_csv("ref/country_pop.csv",
                          col_types = cols(`Indicator Code` = col_skip(),
                                           `Indicator Name` = col_skip(),
                                           X65 = col_skip()),
                          skip = 4)
countries_pop <- select(countries_pop,
                        country_name = `Country Name`,
                        country_code = `Country Code`,
                        pop = `2019`)

# Read in country ISO codes for matching
country_codes <- read_csv("ref/country-codes_csv.csv")
country_codes <- country_codes %>%
  select(official_name_en,
         iso2 = `ISO3166-1-Alpha-2`,
         iso3 = `ISO3166-1-Alpha-3`)

# Get country slugs from API: https://api.covid19api.com/countries
country_slugs_req <- GET("https://api.covid19api.com/countries")
country_slug_response <- content(country_slugs_req, as = "text", encoding = "UTF-8")
country_slug <- fromJSON(country_slug_response)

# Join country slugs to codes
# We end up with 2 country name cols here
country_codes_slugs <- country_codes %>%
  inner_join(country_slug,by=c("iso2" = "ISO2"))

# Add population column
country_all <- inner_join(country_codes_slugs,select(countries_pop,c(country_code,pop)),
                                      by=c("iso3" = "country_code"))

# Define App UI -----------------------------------------------------------

ui <- fluidPage(
  h2("Coronavirus case rate dashboard"),
  p("This dashboard shows the 7-day coronavirus case rate for all countries."),
  selectInput(inputId = "query_country",
              label = "Choose a country:",
              choices = c("",country_all$official_name_en)),
  submitButton("Submit"),
  hr(),
  textOutput("txt"),
  br(),
  uiOutput("ui_plot_caserate")
  )

# Define App Server -----------------------------------------------------------

server <- function(input, output) {
  

  ## Country dataframe -------------------------------------------------------------------------------------
  
  country_df <- reactive({
    if(nchar(input$query_country)>1) {
      
      # get country population and slug
      c_pop <- country_all$pop[country_all$official_name_en == input$query_country]
      c_slug <-  country_all$Slug[country_all$official_name_en == input$query_country]
      
      # query the API for that country
      c_request <- GET(url = paste0("https://api.covid19api.com/total/country/",
                                    c_slug,
                                    "/status/confirmed?from=2020-03-01T00:00:00Z"))
      c_response <- content(c_request, as = "text", encoding = "UTF-8")
      c_df <- fromJSON(c_response, flatten = TRUE) %>%  data.frame()
      
      print(nrow(c_df))
      
      if(nrow(c_df)>0) {
        c_df %>%
          # correct negative new cases to zero
          mutate(new_cases = pmax(Cases - lag(Cases),0),
                 Date = as.Date(Date),
                 week_rate = round(
                   (roll_sum(new_cases, 7, align = "right", fill = NA) / c_pop * 100000),
                   digits=2))
      } else {
        c_df
      }
    }
  })
  

  ## Country and population text -------------------------------------------------------------------------
  
  output$txt <- renderText({
    if(nchar(input$query_country)>1) {
      pop <- country_all$pop[tolower(country_all$official_name_en) == tolower(input$query_country)]
      if(nrow(country_df())>0) {
        paste0(input$query_country,
               ", population ",
               format(pop,big.mark=",",scientific=FALSE),
               ", has reported ",
               format(last(country_df()$Cases),big.mark=",",scientific=FALSE)
               ," total cases.")
      } else {
        paste0(input$query_country,
              ", population ",
              format(pop,big.mark=",",scientific=FALSE),", has no reported cases.")
      }
    }
  })
  
  ## Case rate plot --------------------------------------------------------------------------------------
  
  output$plot_caserate <- renderPlot({
    if(nrow(country_df())>0) {
      ggplot(country_df(),aes(x=Date,y=week_rate)) +
        geom_line(size=1,color="#444444") +
        geom_hline(yintercept=20,size=1,color="#00b3b3") +
        annotate(geom="text", x = max(country_df()$Date)+3,
                 y=tail(country_df()$week_rate,n=1),
                 label=tail(country_df()$week_rate,n=1)) +
        ggtitle(paste("Coronavirus case rate in",input$query_country)) +
        ylab("Cases per 100,000 per week") +
        scale_x_date(date_breaks = "1 month",
                     date_labels = "%b %Y") +
        theme_minimal() +
        theme(axis.text=element_text(size=16),
              axis.text.x=element_text(angle = -90, hjust = 0.5, vjust = 0.5),
              axis.title=element_text(size=14),
              axis.title.x=element_blank(),
              plot.title=element_text(size=20))
    }
  })

  ## Conditional UI for case rate plot ------------------------------------------------------------------
  
  output$ui_plot_caserate <- renderUI({
    if(nchar(input$query_country)>1) {
     plotOutput(outputId = "plot_caserate")
    }
  })
}


# Run app -----------------------------------------------------------------------------------------------
shinyApp(ui = ui, server = server)