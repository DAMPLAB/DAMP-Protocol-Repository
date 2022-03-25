needs "Cloning Libs/Cloning"
needs "Standard Libs/Debug Lib"

#Should have the tech prepare the sample for pickup in some standardized way and send an email to the user that their samples are ready for pickup.
#After this protocol is run, the samples are officially "outside" Aquarium.
#Users can then pickup samples whenever.
INPUT = "Sample being picked up"

class Protocol
  include Cloning
  include Debug
  
  def main
    
    current_taken_items = []
    input_volumes = {INPUT => 0}
    #robust_make ["Sample being picked up"], current_taken_items
    check_user_inputs [INPUT], input_volumes, current_taken_items
    return {} if check_for_errors
    robust_take_inputs [INPUT], current_taken_items, interactive: true
    
    if debug
        operations[0].input(INPUT).item.associate("test key", "test value", (Item.find(244232).upload "sequencing_results"))
    end
    
    show do
        title "Print out labels"
        note "On the computer near the label printer, open Excel document titled 'Sample pickup template'." 
        note "Copy and paste the table below to the document and save as #{operations.running.first.input(INPUT).item.id}."
        
        table_matrix = Array.new(3) {Array.new}
        table_matrix[0] = ["Item ID", "User Name", "Sample Name", "Label for top of tube"]
        i = 1
        operations.running.each do |op|
            op.input_array(INPUT).each do |input|
                table_matrix[i] = ["Item ID: " + input.sample.id.to_s, "User Name: " + input.sample.user.name[0,16], "Sample Name: " + input.sample.name[0,16], input.sample.name[0,8]]
                i += 1
            end
        end
        
        table table_matrix
        
        check "Open the Dymo Label software and select 'File' --> Open --> 'Sample Pick Up Template'."
        check "Select 'File' --> 'Import Data and Print' --> 'New'"
        check "A window should pop up. Under  'Select Data File' enter #{operations.running.first.input(INPUT).item.id} and set 'Total' to #{operations.running.length}. Select 'Finish.'"
        check "Select the Excel file through 'Browse'"
        check "Click on 'Next'"
        check "Select 'use first row as field names' box."
        check "Drag and drop each field to the label. Each field should be placed on a new line." 
        check "Click on 'next' and 'print'"
        check "Collect labels and put on items with matching item IDs."
    end
    
    items_by_address = {}
    operations.running.each do |op|
        op.temporary[:address_string] = [op.input("Recipient Name").value, op.input("Address Line 1").value, op.input("Address Line 2").value, op.input("Address Line 3").value].join("</br>")
        op.input_array(INPUT).each do |input|
            if items_by_address.keys.include? op.temporary[:address_string]
                items_by_address[op.temporary[:address_string]] << input.item
            else
                items_by_address[op.temporary[:address_string]] = [input.item]
            end
        end
    end
    
    log_info "items_by_address", items_by_address
    
    items_by_user = {}
    operations.running.each do |op|
        op.input_array(INPUT).each do |input|
            if items_by_user.keys.include? op.user
                items_by_user[op.user] << input.item
            else
                items_by_user[op.user] = [input.item]
            end
        end
    end
    
    show do
        title "Mail items to users"
        items_by_address.each do |address, items|
            check "Mail items #{items.to_sentence} to the following address: </br> #{address}"
        end
        note "After this step, notification emails will be sent to users. This may take up to a few minutes."
    end
    
    items_by_user.each do |user, items|
        body = "
        Hello #{user.name},<br/><br/>
        The following items have been shipped. Please email #{Parameter.get_string('smtp_email_address')} for questions or more information.<br/><br/>"
        file_paths = {}
        items.each do |item|
            body << "<b>Item ID:</b> #{item.id} <b>Sample Name:</b> #{item.sample.name}<br/>"
            item.associations.each do |key, value| 
                body << "&nbsp;&nbsp;&nbsp;&nbsp;#{key}: #{value}<br/>"
                if item.upload key
                    file_paths[item.upload(key).name] = item.upload(key).path
                end
            end
        end
        send_email user.name, (user.parameters.find { |p| p.key == 'email'}.value), "DAMP Lab items shipped", body, file_paths if user.parameters.find { |p| p.key == 'email'}
    end
    
    operations.each do |op|
        op.input_array(INPUT).items.each do |item|
            item.mark_as_deleted
        end
    end
    
    return {}
    
  end
  
end
