require 'json'
# require 'opentrons'
needs "Cloning Libs/OpenTronsMonkey"
needs "Standard Libs/Debug Lib"

# These slots won't be filled automatically but can still have labware assigned to them explicitly.
RESERVED_SLOTS=['10']

module OpenTronsAq
    include Debug
    
    #include OpenTrons
    include OpenTronsMonkey
    # Opentrons.class_eval { include OpenTronsMonkey}
    
    def run_protocol(protocol)
        filename = 'OT2_protocol_' + (rand(1000) + 100).to_s + '.py'
        
        file = Tempfile.new(filename)
        file.write(protocol.text)
        file.close
        
        # u = Upload.new
        # File.open(file.path) do |f|
        #     u.upload = f
        #     u.name = filename
        #     u.job_id = operations[0].jobs[-1].id
        #     u.save
        #     operations.each do |operation|
        #       operation.associate :protocol_file, "File upload #{filename}", u, duplicates: true 
        #     end
        # end
        
        #DEBUGGING:
        # show do
        #     protocol.rack_layouts.each do |layout|
        #         note "layouts are #{layout}"
        #     end
        # end
        
        show do
            title "Run protocol on OT2 robot"
            # u.url
            #check "<a href=\"#{u.url}\" download=\"#{filename}\">Download OpenTrons Protocol</a>"
            check "Drag protocol into OT2 app and follow instructions to calibrate."

            protocol.rack_layouts.each do |layout|
                table_matrix = Array.new
                layout["layout"].each_with_index do |row, i|
                    table_matrix[i] = Array.new #added during the meeting
                    # note "row is : #{row} and i is #{i}"
                    row.each_with_index do |item, j|
                        # note "i is #{i} and j is #{j} and itemid is #{item.id}"
                        if !(item) || (item.is_a?(AqDummyItem) && !(item.name))
                            table_matrix[i][j] = "None"
                        elsif item.is_a? AqDummyItem
                            table_matrix[i][j] = {content: item.name, check: true}
                        else
                            table_matrix[i][j] = {content: "Item ID: #{item.id}", check: true} 
                        end
                    end
                end
                
                check "Load items into #{layout["display_name"]} (#{layout["model"]}) according to the following table:"
                table table_matrix
            end
            
            warning "Warning: remove all caps from tubes and carefully follow instructions in the app!"
            warning "Never load frozen items onto the deck!"

            check "Set up OT2 deck according to the following table:"
            table protocol.deck_layout
            
            check "Run OT2 protocol using the app."
        end
    end
    
    class OTAqProtocol < OTProtocol
        
        include Debug
        
        def initialize(params: {})
            super(params)
            designer_application = "OpenTronsAq"
            @labware_definitions = []
            @wells_by_item_id = {}
        end
        
        def to_hash
            as_hash = super
            as_hash["labware-definitions"] = @labware_definitions
            return as_hash
        end
        
        def text
            return "jp = " + to_json + "\n\n" + get_code('Universal OT Template').content
        end
        
        # Note: This is really hacky for multiple reasons.
        # Adds a labware definition from an Aquarium library.
        def add_labware_definition(name)
            @labware_definitions << JSON.parse(get_code(name).content)
            labware.labware_definitions << JSON.parse(get_code(name).content)
        end
        
        def find_well(aq_item)
            return @wells_by_item_id[aq_item.id]
        end

        # Generates a list of hashes with display names, models, and contents of labware as keys and 2D arrays of aq items (or nils)
        def rack_layouts
            layouts = []
            labware.labware_hash.each do |key, labware_item|
                current_layout = {"display_name" => labware_item.display_name, "layout" => [], "model" => labware_item.model}
                at_least_one_item = false
                labware_item.well_list.each_with_index do |col, j|
                    col.each_with_index do |well, i|
                        if current_layout["layout"][i].nil?
                            current_layout["layout"][i] = Array.new
                        end
                        current_layout["layout"][i][j] = well.item
                        at_least_one_item = true if well.item
                    end
                end
                layouts << current_layout if at_least_one_item
            end
            return layouts
        end

        # Returns deck layout as a 2D array ready to be displayed in Aq with table krill command.
        def deck_layout
            layout = Array.new(4) {Array.new(3) {"None"}}
            labware.labware_hash.each do |key, labware_item|
                i = 3 - ((labware_item.slot.to_i - 1) / 3)
                j = (labware_item.slot.to_i - 1) % 3
                layout[i][j] = {content: "Name: #{labware_item.display_name}, Model: #{labware_item.model}", check: true}
            end
            return layout
        end
        
        # Finds a Code by the name of its Library
        private def get_code name
            lib = Library.where(name: name)[-1]
            # return most recent version.
            return Code.where(parent_id: lib.id)[-1]
        end

        # Allocates a number of wells, reserving and returning them as an Array. Will create new labware 
        # of labware_type if create_labware = 1 (default) and no well is found. create_labware of 0 never 
        # creates labware. create_labware of 2 always creates labware.
        def allocate_wells(num, labware_type, create_labware: 1)
            allocated_wells = []
            labware_item = get_labware_item labware_type, create_labware

            num.times do
                well = find_avail_well labware_item
                if !well
                    labware_item = get_labware_item labware_type, 2
                    well = find_avail_well labware_item
                end

                well.allocated = true
                allocated_wells << well
            end

            return allocated_wells
        end

        # Assigns wells to items and returns wells. Also adds well data assoc to items.
        # Warning: currently cannot handle items w/ multiple labware types.
        def assign_wells(aq_items, wells=nil, create_labware: 1) 
            if wells
                if !(wells.length == aq_items.length)
                    raise ArgumentError.new "Number of items (#{aq_items.length}) and wells (#{wells.length}) do not match."
                end
            else
                labware_type = aq_items[0].object_type.data_object[:opentrons_labware]
                if labware_type
                    wells = allocate_wells aq_items.length, labware_type, create_labware: create_labware
                else
                    raise ArgumentError.new "No opentrons_labware value found for Container type #{aq_items[0].object_type}."
                end
            end

            wells.each_with_index do |well, i|
                well.item = aq_items[i]
                #aq_items[i].well = well
                @wells_by_item_id[aq_items[i].id] = well
            end
        end

        def dummy_item(name=nil)
            return AqDummyItem.new(name)
        end

        # Utility function for finding unallocated well in labware item.
        private def find_avail_well(labware_item)
            labware_item.wells.each do |well|
                if !(well.allocated)
                    return well
                end
            end
            return nil
        end

        # Utility function for creating or finding labware items.
        private def get_labware_item(labware_type, create_labware)
            if create_labware == 2
                return labware.load(labware_type, labware.free_slots[-1], "#{labware_type}-#{labware.free_slots[-1]}")
            else
                labware.labware_hash.each do |key, labware_item|
                    if labware_item.model == labware_type
                        return labware_item
                    end
                end

                # If nothing was found, create new or throw error.
                if create_labware == 1
                    return labware.load(labware_type, labware.free_slots[-1], "#{labware_type}-#{labware.free_slots[-1]}")
                else
                    raise ArgumentError.new "create_labware set to 0 (never) and no well of type #{labware_type} found."
                end
            end
        end
    end
    
    module WellMixin
        attr_accessor :item, :allocated
    end
    OpenTronsMonkey::Well.class_eval {include WellMixin}
    #OpenTrons::Well.class_eval {include WellMixin}
    
    # very bad
    class OpenTronsMonkey::Labware
        alias_method :old_free_slots, :free_slots
        
        def free_slots
            slots = (1..12).to_a.map{|x| x.to_s}
			taken_slots = labware_hash.map {|key, item| item.slot}
			return slots.select{|x| !(taken_slots.include? x)} - RESERVED_SLOTS
        end
    end
    
    # This item behaves like an Aq item for purposes of the module, but is not added to the Aquarium database.
    class AqDummyItem
        attr_accessor :name, :id
        def initialize(name=nil)
            @name = name
            @id = rand(100000)
        end
    end
end
