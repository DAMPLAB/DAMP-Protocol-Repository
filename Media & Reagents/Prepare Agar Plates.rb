#Directs tech to make 500 mL = 2 sleeves = 50 plates of untreated agar plates with the specified antibiotic + XGAL + IPTG.
needs "Standard Libs/Manager Lib"

class Protocol
    include Manager
    
	def main
		operations.each do |op|
			show do
				title "Weigh LB agar powder"
				check "Get out a 1L glass bottle"
				check "Weigh out 16g of LB Agar (Powder). You can find it on chemical shelf by the OpenTrons."
				warning "Use LB Agar, not LB!"
				note "The material used to weigh chemicals is in 'Weight Material' drawer."
				check "Add the LB agar powder to the 1L glass bottle."
				check "Clean the scale and benchtop with wet paper towel."
			end
            
			show do
				title "Add dH2O"
				check "Get out a 500mL graduated cylinder."
				check "Measure 500mL of dH2O using the graduated cylinder and add it to the 1L bottle."
				check "Screw the lid of the bottle on tightly and mix by turning the bottle upside down several times. Thorough mixing is not required, since the rest will disolve upon autoclaving."
				check "After mixing, unscrew the lid slightly so that it is loose and can freely rotate!"
				warning "Autoclaving media with the lid screwed on tightly will cause an explosion!"
			end
			
			autoclave_items "500 ml bottle of LB agar", 500
			
			show do
			    title "Lable the plates"
			    check "While waiting for the LB agar, color code each plate with respected color according to the figures."
			    image 'Agar_Plates/Antibiotic_Color_Code.jpg'
			    image 'Agar_Plates/Color_Code_Example.jpg'
			end
			
			show do
			    title "Allow LB agar to cool slightly and lable the plates"
			    check "Allow LB agar to cool only to the point where you can touch it for ~4 seconds without heat resistant gloves."
			    warning "Allowing agar to cool too much will cause it to solidify."
			end
			
			show do
			    title "Add antibiotic, X-Gal, and IPTG"
			    check "Turn on bunsen burner and work close to flame."
			    warning "Do not add these items until agar is cool enough to touch without needing heat-resistant gloves."
			    check "Add 500 ul of #{op.input("Antibiotic").val} to the LB agar."
			    note "Antibiotics can be found in antibiotic box in small -20."
			    check "Add 500 ul of the 0.5 M solution of IPTG to the LB agar."
			    check "Add 500 ul of the 20 mg/ml solution of X-Gal to the LB agar."
			    note "You can find IPTG and X-Gal solutions in the door of the large -20C freezer."
			    check "Fully screw on lid and mix by gently swirling (avoid bubbles)."
			    warning "Continue to next steps immediately before agar solidifies."
			end
			
			show do
			    title "Pour plates"
			    check "Get out 1 sleeve (25 plates) of 100mmx15mm split (two compartment) polystyrene petri plates"
			    warning "Do not discard sleeves for plates."
			    check "Swirl the bottle of agar every few minutes to ensure that chunks of agar do not form."
			    check "Use a 25 mL serological pipette to add 20 mL of LB agar into each plate (if the plate is split, put 10 ml in each side of the plate). Gently swirl to cover the full surface of the plate."
			    bullet "You can draw up 22 mL and dispense 20 mL to avoid bubbles."
			    bullet "You can use the same serological pipette for all plates."
			    check "Allow plates to cool at room temp for 30 minutes with the cover partially open. Make sure the flame is on while the covers are partially open!"
			    timer initial: { hours: 0, minutes: 30, seconds: 0}
			    check "Turn off bunsen burner!"
            end
            
            show do
                title "Label and store plates"
                check "After plates have fully solidified, close the covers."
                check "Write the label on the sleeve: \"#{op.input("Antibiotic").val}, #{Date.today.strftime('%d %b %Y')}\""
                check "Leave the plates on the bench for 1 day before placing them back in sleeves, then place the sleeves in a drawer labeled with DAMP in the walk-in fridge."
            end
		end
	end
end
