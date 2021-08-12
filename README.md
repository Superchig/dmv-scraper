# DMV Scraper
This scrapes the CA DMV's automobile driving test appointment system,
searching their offices for available driving test dates and sorting the
offices by distance to a specified address.

## Requirements
This relies on Google's Distance Matrix API, so it requires an API key, stored
in a file named maps_api_key.

Your driver's license / instructional permit number, as well as a date of
birth, are required by the CA DMV to set up a driving appointment.

The following files are required, as a result.
- driver_license_number - Driver License Number
- maps_api_key - Google API key
- dob - Date of Birth
  - Formatted like 11051999 for Nov 5, 1999
- starting_addr - Starting Address

## TODO
- [ ] Store necessary configuration information in a json file, with an
      example
