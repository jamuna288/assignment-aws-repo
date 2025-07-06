
def run_agent(input_text):
    """
    Enhanced agent function that provides intelligent flight recommendations
    with improved response handling and auto-deployment testing.
    Version: 2.0 - Auto-deployment test
    """
    
    # Simple rule-based responses for demonstration
    input_lower = input_text.lower()
    
    if "delay" in input_lower or "delayed" in input_lower:
        return {
            "message": "We sincerely apologize for the flight delay. Here are your options:",
            "recommendations": [
                "Check with gate agent for updated departure time",
                "Consider rebooking on next available flight",
                "Request meal vouchers if delay exceeds 3 hours",
                "Contact customer service for accommodation if overnight delay"
            ],
            "passenger_message": "We understand your frustration and are working to get you to your destination as quickly as possible."
        }
    elif "cancel" in input_lower:
        return {
            "message": "Flight cancellation assistance:",
            "recommendations": [
                "Automatic rebooking on next available flight",
                "Full refund if you choose not to travel",
                "Hotel accommodation for overnight delays",
                "Meal vouchers and transportation"
            ],
            "passenger_message": "We apologize for the inconvenience. Our team is ready to assist with rebooking or refunds."
        }
    elif "weather" in input_lower:
        return {
            "message": "Weather-related flight disruption guidance:",
            "recommendations": [
                "Monitor weather conditions at destination",
                "Consider flexible rebooking options",
                "Check airline app for real-time updates",
                "Prepare for possible extended delays"
            ],
            "passenger_message": "Weather safety is our priority. We'll resume operations as soon as conditions improve."
        }
    else:
        return {
            "message": "General flight assistance:",
            "recommendations": [
                "Check flight status regularly",
                "Arrive at airport with extra time",
                "Keep important documents handy",
                "Download airline mobile app for updates"
            ],
            "passenger_message": "Thank you for flying with us. We're here to help make your journey smooth."
        }
