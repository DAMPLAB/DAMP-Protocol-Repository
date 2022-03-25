# Verify Fragment Protocol
needs "Standard Libs/Debug Lib"
needs "Cloning Libs/Cloning"

class Protocol
    include Debug
    include Cloning
    
    def main
        operations.retrieve(interactive: false )
        operations.sort_by! {|op| [op.input("Fragment").item.id, op.input("Fragment").column]}
        
        gel_ids = operations.map {|op| op.input("Fragment").item.id}.uniq
        gels = gel_ids.map {|id| operations.select {|op| op.input("Fragment").item.id == id}}
        gels.each {|gel| gel.extend(OperationList)}
        gel_uploads = {}
        
        gels.each do |gel|
            show do
                title "Image gel #{gel[0].input("Fragment").item.id}"
                warning "Always wear gloves when dealing with gels and gel imager."
                check "Pull out drawer of gel imager. Clean the XcitaBlue conversion screen and the razor blade with ethanol."
                warning "Be careful while dealing with the razor blade!"
                check "Check that the filter is set to position 1 (top of gel imager)."
                check "Place gel #{gel[0].input("Fragment").item.id} on the center of the XcitaBlue conversion screen, and push in drawer of gel imager."
                check "Open Image Lab program. Click File->Open and select the \"Agarose Gel EtBr\" protocol under \"Documents\\My Documents\\Image Lab Protocols\"."
                check "Select \"Position Gel\". Confirm that the gel is centered and that zoom is set correctly. Open door to adjust gel if necessary."
                check "Select \"Run Protocol\"."
            end
            
            data = show do
                title "Export and print image"
                check "While the image window is selected, click File->Export->Export for Publication... Change resolution to 600 dpi and click \"Export\". Save to folder  \"Documents\\Image Lab Images\" with the filename \"#{gel[0].input("Fragment").item.id}\"."
                check "Upload the image:"
                upload var: "gel_image"
                check "In the image window, select image transform button and check \"Invert image display\"."
                check "Print the image (using MITSUBISHI P95D) and give printout to lab manager."
                warning "Wait for the image to finish uploading before continuing!"
            end
            
            gel.each do |op|
                op.associate(:image,{},Upload.find(data[:gel_image][0][:id])) if !debug
                op.associate(:lane_in_gel, "Operation output (#{op.input("Fragment").sample.name}) can be seen in lane #{op.input("Fragment").column + 2}. Lanes numbered left to right with ladder in lane 1.")
            end
            
            show do
                title "Verify Fragment Lengths"
                note "Note: lane 1 is reserved for the ladder"
                table gel.start_table
                .custom_column(heading: "Gel ID") { |op| op.input("Fragment").item.id }
                .custom_column(heading: "Lane") { |op| op.input("Fragment").column + 2 }
                .custom_column(heading: "Expected Length") { |op| op.input("Fragment").sample.properties["Length"] }
                .get(:correct, type: 'text', heading: "Does the band match the expected length? (y/n)", default: "y")
                .end_table
            end
            
            gel.each do |op|
                if op.temporary[:correct].upcase.start_with?("N")
                    op.error :incorrect_length, "No fragment found with the expected length."
                end
            end
            
            return {} if check_for_errors
            
            gel.make
            
            choice = show do
                title "Clean Up"
                check "Close image and protocol windows inside Image Lab program."
                check "Double check that the drawer of the gel imager is pushed in."
                check "Dispose of the gel and any gel parts by placing it in the gel waste container. Spray the surface of the transilluminator with ethanol and wipe until dry using a paper towel."
                check "Clean up the gel box and casting tray by rinsing with water. Return them to the gel station."
                check "Dispose of gloves used for extracting fragment."
            end
            gel[0].input("Fragment").item.mark_as_deleted
            #current_gel_ops[0].output("Gel Lane").collection.id.to_s
        end
        
        return {}
    end

end
