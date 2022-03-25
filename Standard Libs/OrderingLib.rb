module Ordering
    #https://github.com/gimite/google-drive-ruby
    require 'google_drive'
    
    #The google drive file ID for the DAMP Lab ordering spreadsheet. This should be shared with damplabnorthaquarium@gmail.com
    #Just change this to post to a different order sheet!
    ORDER_SHEET_ID = "12FhpjhvToSC50i9cJ8rU5ygyUr-AfS4Bhe57VQ2bqNg"
    TEST_ORDER_SHEET_ID = "1OGmMxobolqQOrcWyvqiMwNK7ZqnMfEPAXTGhTgekdqQ"
    
    #OAuth identification file (in working directory on server)
    #This doesn't need to be changed to use a new order sheet!
    #Note: Need to run "session = GoogleDrive::Session.from_config(GOOGLE_SHEETS_CONFIG_PATH)" from rails console the first time you use this config file to get a confirmation key. See documentation on the google_drive gem for more info.
    GOOGLE_SHEETS_CONFIG_PATH = "google_sheets_config.json"
    
    #Adds an entry to the ordering google sheet.
    #the order_info argument should be an array of the form [name, vendor, manufacturer, catalog_number, quantity, unit_price_in_dollars]
    #For example: place_order ["Fisherbrand Plastic Petri Dishes", "Fisher", "Fisher", "S33580A", 1, 44.21]
    #Note that the catalog number is a string (in parentheses) and the quantity and price are numbers (no parentheses).
    def place_order order_info
        session = GoogleDrive::Session.from_config(GOOGLE_SHEETS_CONFIG_PATH)
        
        #Find the first empty row in the second sheet.
        order_sheet = session.spreadsheet_by_key(debug ? TEST_ORDER_SHEET_ID : ORDER_SHEET_ID).worksheet_by_title("Expenses_LCP")
        i = 1
        x = order_sheet[i, 1]
        while x.instance_of?(String) && x.length > 0
            i += 1
            x = order_sheet[i, 1]
        end
        #Add the order to the google sheet.
        order_info.each_with_index{|v, j| order_sheet[i, j+1] = v}
        order_sheet.save
    end
    
    #Adds an entry to the ordering google sheet.
    def place_seq_order order_info
        session = GoogleDrive::Session.from_config(GOOGLE_SHEETS_CONFIG_PATH)
        
        #Find the first empty row in the second sheet.
        order_sheet = session.spreadsheet_by_key(debug ? TEST_ORDER_SHEET_ID : ORDER_SHEET_ID).worksheet_by_title("Quintara_PO")
        i = 1
        x = order_sheet[i, 1]
        while x.instance_of?(String) && x.length > 0
            i += 1
            x = order_sheet[i, 1]
        end
        #Add the order to the google sheet.
        order_info.each_with_index{|v, j| order_sheet[i, j+1] = v}
        order_sheet.save
    end
    
    #Adds an entry to the ordering google sheet.
    def place_DNA_order order_info
        session = GoogleDrive::Session.from_config(GOOGLE_SHEETS_CONFIG_PATH)
        
        #Find the first empty row in the second sheet.
        order_sheet = session.spreadsheet_by_key(debug ? TEST_ORDER_SHEET_ID : ORDER_SHEET_ID).worksheet_by_title("IDT_PO")
        i = 1
        x = order_sheet[i, 1]
        while x.instance_of?(String) && x.length > 0
            i += 1
            x = order_sheet[i, 1]
        end
        #Add the order to the google sheet.
        order_info.each_with_index{|v, j| order_sheet[i, j+1] = v}
        order_sheet.save
    end
end

