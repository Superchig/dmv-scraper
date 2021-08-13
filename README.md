# DMV Scraper
This scrapes the CA DMV's automobile driving test appointment system,
searching their offices for available driving test dates and sorting the
offices by distance to a specified address.

## Requirements
This relies on Google's Distance Matrix API, so it requires an API key, stored
in a file named maps_api_key.

Your driver's license / instructional permit number, as well as a date of
birth, are required by the CA DMV to set up a driving appointment.

A default config.yaml is provided.

## TODO
- [x] Store necessary configuration information in a yaml file, with an
      example
- [x] Send email regarding nearby offices with available dates, according to
      --target-date CLI option
