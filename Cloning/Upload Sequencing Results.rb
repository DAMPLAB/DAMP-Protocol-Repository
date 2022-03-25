needs "Standard Libs/Debug Lib"
needs "Cloning Libs/Cloning"

class Protocol
  include Debug
  include Cloning
  ORDER = "Plasmid"

  def main

    # debuggin'
    if debug
      operations.first.set_input_data ORDER, :tracking_num, 12345
    end
    
    operations.retrieve interactive: false

    tracking_num = operations.first.input_data(ORDER, :tracking_num)
    
    results_info = show do
      title "Check if Sequencing results arrived?"
      
      check "Go to the <a href='http://www.quintarabio.com/' target='_blank'>QUINTARA website</a>, log in with lab account (Username: damplab@bu.edu)."
      check "In 'Sanger Sequencing' tab, find the Reference ID #{tracking_num}, and check if the sequencing results have shown up yet."
      
      select ["Yes", "No"], var: "results_back_or_not", label: "Do the sequencing results show up?"
    end

    raise "The sequencing results have not shown up yet." if results_info[:results_back_or_not] == "No"

    show do
      title "Download Quintara Sequencing Results zip file"
      check "Click the tab 'ab1', which should download a zip file named #{tracking_num}.zip."
      check "Save the zip file in 'Sequencing Results' folder, on Desktop."
      #check "Upload the #{tracking_num}_ab1.zip file here."
      #check "Wait until the download is complete."
    end
    
    sequencing_uploads = show do
      title "Upload individual sequencing results"
      check "Unzip the downloaded zip file named #{tracking_num}_ab1.zip."
      check "If you are on a Windows machine, open the #{tracking_num}.zip file, then click Extract."
      check "Upload all the unzipped ab1 files by navigating to the upzipped folder."
      check "You can use Shift command to select all files."
      check "Wait until all the uploads finished (a number appears at the end of file name). "
      
      upload var: "sequencing_results"
    end

    operations.each do |op|
      op.pass("Plasmid","Plasmid")
      # find sequencing result for op
      upload_results = sequencing_uploads[:sequencing_results] || []
      sequencing_upload_id = upload_results.find { |result| result[:name].include? op.input(ORDER).item.id.to_s }
      if sequencing_upload_id
        upload = Upload.find(sequencing_upload_id[:id])
        op.output("Plasmid").item.associate :sequencing_results, "Please click \"Seq OK\" or discard the item after reviewing sequencing data.", upload
      end
      
      #pass through plasmid 
    end
    
    ops_by_user = {}
    operations.each do |op|
        user = User.find(op.user_id)
        if ops_by_user.keys.include? user
            ops_by_user[user] << op
        else
            ops_by_user[user] = [op]
        end
    end
    
    ops_by_user.each do |user, ops|
        body = "
        Hello #{user.name},<br/><br/>
        DAMP Lab North has received sequencing results for the following items. Please follow the links provided to view your items in the inventory. To accept sequencing results and continue with downstream operations, click the green \"Seq OK\" button when viewing an item in your inventory. If a sequence is incorrect, discard the item. For questions or additional information, email #{Parameter.get_string('smtp_email_address')}.<br/><br/>
        #{
            ops.map { |op|
                "<b>Item:</b> #{op.input("Plasmid").item.id.to_s} <b>Sample:</b> #{op.input("Plasmid").sample.name} <b>Plan:</b> #{op.plan.id}. <a href=\"http://54.190.2.203/browser?sid=#{op.input("Plasmid").sample.id.to_s}\">View in inventory</a>"}.join("<br/>")
        }"
        if user.parameters.find { |p| p.key == 'email'}
            send_email user.name, user.parameters.find { |p| p.key == 'email'}.value, "DAMP Lab Seqeuncing Results", body
        end
    end

    return {}
    
  end

end
