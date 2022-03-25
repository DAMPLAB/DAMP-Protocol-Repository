#Directs tech to make 5 bottles of 100 mL LB media each (500mL total).
needs "Standard Libs/Manager Lib"

class Protocol
    include Manager
    
	def main
		operations.each do |op|
			show do
				title "Weigh LB powder"
				check "Get out a 1L plastic beaker."
				check "Weigh out 10g of LB (Powder). You can find it on chemical shelf by the OpenTrons."
				warning "Use LB, not LB Agar!"
				note "The material used to weigh chemicals is in 'Weight Material' drawer."
				check "Add the LB powder to the beaker."
				check "Clean the scale and benchtop with wet paper towel."
			end
            
			show do
				title "Add dH2O"
				check "Get out a 500ml graduated cylinder."
				check "Measure 500ml of dH2O using the graduated cylinder and add it to the beaker."
				check "Add a large white stir bar to the beaker. Stir bars are also found in \"Weight Material\" drawer."
				check "Confirm that the heater on the mixing plate is turned off and that the plate is cool."
				check "Add beaker to mixing plate. Mix at setting of 2 until no clumps remain."
			end
			
			show do
			    title "Transfer to 100ml bottles"
			    check "Get out 5 100ml autoclavable glass bottles (in large labware cabinet)."
			    check "Add 100ml of LB to each bottle and loosely cap."
			    warning "Do not fully screw on caps! Bottles will explode in the autoclave!"
			    check "Rinse empty large beaker and place in sink."
			end
			
			autoclave_items "100 ml bottles of LB", 100
            
            show do
                title "Store"
                check "After LB has cooled, store at the cell culture station."
            end
		end
	end
end
