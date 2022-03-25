module Manager
    
    #Directs tech to autoclave items. First argument is the name of the item or an array of names. Second argument is the LARGEST volume of any of the items in mL (set to 0 for dry items).
    #Example usages: 
        #autoclave_items ["100 ul tips", "200 ul tips"], 0
        #autoclave_items "500 ml LB Agar", 500
    def autoclave_items items, vol
	    items = Array(items)
	    show do
	        title "Add autoclave tape to #{items.to_sentence}"
	        check "Add fresh autoclave tape to #{items.to_sentence}. Autoclave tape can be found in \"Autoclave Tapes\" drawer."
	    end
	    
		show do
			title "Set up autoclave"
			check "Check if an autoclave is available. The \"Open Door\" button should be visible."
			warning "Do not Abort a running autoclave cycle."
			check "Put on heat-resistant autoclave gloves."
			warning "Using the autoclave without heat-resistant gloves will cause burns!"
			check "Click \"Open Door\". If any bins are already in the autoclave, take them out and set them on the bench."
		end
		
		show do
		    title "Load autoclave"
	        check "Place #{items.to_sentence} in an autoclave bin."
	        check "Double check that all container lids are not screwed on all the way, and place the bin in the autoclave."
	        warning "Autoclaving items with the lid screwed on tightly will cause an explosion!"
			check "Hold the \"Close Door\" button to close the autoclave door."
		end
		
		show do
		    title "Select and start autoclave cycle"
		    if vol > 0
		        #Calculate sterilization time and round to nearest 5.
		        if vol >= 75 && vol <= 2000
		            ster_time = ((((0.9*Math.sqrt(500) + 16.0)*2).round(-1))/2.0).round
	            else
	                raise "Volume of #{vol} mL is out of range for autoclave."
	            end
		        check "Click \"Cycle Select\" -> Liquids"
		        check "Edit one of the cycles to have the following settings and select that cycle:"
		        table [
		            ["Chamb. Temp", "Sterilization Time"],
		            ["121C", ster_time.to_s]]
		    else
		        check "Click \"Cycle Select\" -> Gravity"
		        check "Edit one of the cycles to have the following settings and select that cycle:"
		        table [
		            ["Chamb. Temp", "Sterilization Time", "Dry Time"],
		            ["121C", "30", "20"]]
		    end
		    check "Click \"Yes\" to start the autoclave."
		    check "Set a timer to remind yourself to retrieve your bin from the autoclave. Do not allow items to sit in autoclave overnight."
		end
	    
		show do
			title "Retrieve from autoclave"
			check "Put on heat-resistant autoclave gloves."
			warning "Using the autoclave without heat-resistant gloves will cause burns!"
			warning "Do not abort an autoclave cycle while it is running. Wait for it to finish."
			check "Open door of autoclave and take out bin containing #{items.to_sentence}."
		end
	end
end
