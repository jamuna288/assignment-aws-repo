from .llm import llm

def flight_delay_recommendation(input: str) -> str:
    prompt = f"""
    A flight has been delayed and there are operational issues. Here are the details: {input}

    Provide a detailed recommendation:
    - Compose a short, empathetic message for passengers.
    - Suggest alternate flight options (exact)
    """
    return llm.predict(prompt)

from langchain.agents import Tool

flight_delay_tool = Tool(
    name="FlightDelayRecommendation",
    func=flight_delay_recommendation,
    description="Provides recommendations for flight delays and issues."
)


 