require "selenium-webdriver"
require "uri"
require "net/http"
require "json"
require "yaml"
require "date"
require "table_print"

MAX_DATE_QUERIES = 1000

class Office
  attr_accessor :name, :dates_available, :address, :dist_sec

  def initialize(name, dates_available, address, dist_sec)
    @name = name
    @dates_available = dates_available
    @address = address
    @dist_sec = dist_sec
  end

  def to_json(opts)
    hash = {}
    self.instance_variables.each do |var|
      hash[var] = self.instance_variable_get var
    end
    hash.to_json(opts)
  end
end

def tp_offices(offices)
  distance_format = {
    distance: lambda { |office| Time.at(office.dist_sec).utc.strftime("%H:%M:%S") },
  }

  date_count_format = {
    avail_dates: lambda { |office| office.dates_available.size },
  }

  address_format = {
    address: {
      display_method: lambda { |office| office.address },
      width: 50,
    },
  }

  earliest_date_format = {
    earliest: {
      display_method: lambda do |office|
        if office.dates_available.empty?
          "N/A"
        else
          office.dates_available.sort.first.strftime("%b %d %Y")
        end
      end,
    },
  }

  tp(offices, :name, address_format, distance_format, earliest_date_format, date_count_format)
end

if ARGV.size == 1
  input_file = ARGV[0]

  offices = JSON.parse(File.read(input_file)).map do |hash|
    dates = hash["@dates_available"].map { |date_str| Date.parse(date_str) }
    office = Office.new(hash["@name"], dates, hash["@address"], hash["@dist_sec"])
  end

  tp_offices(offices)

  exit
end

driver = Selenium::WebDriver.for :firefox
driver.navigate.to("https://www.dmv.ca.gov/portal/appointments/select-appointment-type")

wait = Selenium::WebDriver::Wait.new

config = YAML.load(File.read("config.yaml"))

# Uses css_selector / querySelector
automobile_button = driver
  .find_element(css: '#appointment-type-selector .appointment-reason__selection [for="DT"] .btn')

automobile_button.click

dl_num_elem = driver.find_element(id: "dlNumber")
dl_num_elem.send_keys(config["driver_license_number"])

dob_elem = driver.find_element(id: "dob")
dob_elem.send_keys(config["dob"])

enter_appt_selection_button = driver
  .find_element(xpath: "/html/body/main/div[2]/div/div[1]/div[1]/section/div[4]/div/div[2]/div/div[2]/button")
enter_appt_selection_button.click

# Wait n seconds for an element to be found, subsequent to this call
# driver.manage.timeouts.implicit_wait = 1

offices = []

curr_page = 0

def find_page_btns(driver)
  driver.find_elements(css: "#location-pagination .pagination__list button.page-numbers").select do |btn|
    /\d+/.match(btn.attribute("innerText"))
  end
end

page_btns = find_page_btns(driver)
page_count = page_btns.size

1.upto(page_count) do |curr_page|
  # 16.upto(17) do |curr_page|
  page_btns = find_page_btns(driver)

  # Make sure we're on the right page
  while page_btns.empty?
    puts "Heading back to location selection from a..."

    edit_loc_btn = driver.find_element(css: 'div.appointment__panel [href="/portal/appointments/select-location"]')
    edit_loc_btn.click

    page_btns = find_page_btns(driver)
  end

  curr_page_btn = page_btns[curr_page - 1]
  curr_page_btn.click

  puts "curr_page: #{curr_page}, btn innerText: #{curr_page_btn.attribute("innerText")}"

  wait.until { driver.find_elements(css: "li.location-results__list-item .search-card__title") }

  title_card_headings = driver
    .find_elements(css: "li.location-results__list-item .search-card__title")

  # puts "title_card_headings: #{title_card_headings}"

  office_names = title_card_headings.map do |heading|
    name = heading.attribute("innerText").split(".")[1]
  end

  page_offices = []

  # Gather the dates for each office
  office_names.each_with_index do |name, index|
    dates_available = nil

    loop do
      begin
        select_loc_btns = driver.find_elements(css: "li.location-results__list-item button.btn--select-loc")

        # Make sure we're on the right page
        while select_loc_btns.empty?
          puts "Heading back to location selection from b..."

          # TODO(Chris): Refactor this edit_loc_btn query into its own function
          edit_loc_btn = driver.find_element(css: 'div.appointment__panel [href="/portal/appointments/select-location"]')
          edit_loc_btn.click

          select_loc_btns = driver.find_elements(css: "li.location-results__list-item button.btn--select-loc")
        end

        puts "select_loc_btns.size: #{select_loc_btns.size}, index: #{index}"

        # Use index to access select_loc_btn, so that we can update select_loc_btns in the loop
        select_loc_btn = select_loc_btns[index]
        select_loc_btn.click

        date_elems = []
        1.upto(MAX_DATE_QUERIES) do |i|
          break unless date_elems.empty?

          # puts "Searching again for dates..."

          date_elems = driver.find_elements(css: "div.rbc-month-row div.rbc-event-allday span.rbc-event-day-num--mobile")

          if i == MAX_DATE_QUERIES
            puts "NOTE: Could not find any dates for #{name}. This may be a bug or a valid result, sorry."
          end
        end

        dates_available = date_elems.map do |elem|
          Date.parse(elem.attribute("innerText"))
        end
      rescue Selenium::WebDriver::Error::StaleElementReferenceError
        # Try again if this error occurs, so don't put anything here intentionally
      else
        break
      end
    end

    page_offices.push(Office.new(name, dates_available, nil, nil))

    # Head back to the appointment page
    wait.until do
      driver.find_element(css: 'div.appointment__panel [href="/portal/appointments/select-location"]')
    end

    edit_loc_btn = driver.find_element(css: 'div.appointment__panel [href="/portal/appointments/select-location"]')
    edit_loc_btn.click

    page_btns = find_page_btns(driver)

    # Make sure we're on the right page
    while page_btns.empty?
      puts "Heading back to location selection from c..."

      edit_loc_btn = driver.find_element(css: 'div.appointment__panel [href="/portal/appointments/select-location"]')
      edit_loc_btn.click

      page_btns = find_page_btns(driver)
    end

    # Head back to the correct page, since the website returns us to page 1 by default
    page_btns[curr_page - 1].click
  end

  address_divs = driver.find_elements(css: "li.location-results__list-item [itemprop=address]")

  # Make sure we're on the right page
  while address_divs.empty?
    puts "Heading back to location selection from d..."

    wait.until { driver.execute_script("return document.readyState") == "complete" }

    edit_loc_btn = driver.find_element(css: 'div.appointment__panel [href="/portal/appointments/select-location"]')
    edit_loc_btn.click

    address_divs = driver.find_elements(css: "li.location-results__list-item [itemprop=address]")
  end

  addresses = address_divs.map do |div|
    div.attribute("innerText").gsub(/[\r\n]/, ", ").gsub("CA", " CA ")
  end

  page_offices.each_with_index do |office, index|
    office.address = addresses[index]
  end

  offices.concat(page_offices)
end

File.write("most_recent_pre.json", JSON.pretty_generate(offices))

starting_addr = config["starting_addr"].gsub(" ", "+")
maps_api_key = config["maps_api_key"]

params = {
  origins: starting_addr,
  # destinations: offices.map { |office| office.address.gsub(' ', '+') }.join('|'),
  key: maps_api_key,
  units: "imperial",
}

dist_secs = []

uri = URI("https://maps.googleapis.com/maps/api/distancematrix/json")

offices.each_slice(10) do |batch|
  puts uri

  params["destinations"] = batch.map { |office| office.address.gsub(" ", "+") }.join("|")

  uri.query = URI.encode_www_form(params)

  res = Net::HTTP.get_response(uri)

  if res.is_a?(Net::HTTPSuccess)
    body = JSON.parse(res.body)

    dist_secs.concat(body["rows"][0]["elements"].map do |elem|
      elem["duration"]["value"]
    end)
  else
    p res
    p res.body
  end
end

# This assumes that offices has already been created
offices.zip(dist_secs).each do |arr|
  office = arr[0]
  dist_sec = arr[1]

  office.dist_sec = dist_sec
end

offices.sort! { |a, b| a.dist_sec <=> b.dist_sec }

File.write("most_recent.json", JSON.pretty_generate(offices))

tp_offices(offices)

print "Press enter to exit: "

gets.chomp

driver.quit
