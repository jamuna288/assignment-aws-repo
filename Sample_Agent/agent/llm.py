
from langchain.chat_models import ChatOpenAI
import os
from dotenv import load_dotenv
load_dotenv()


OPENAI_API_KEY = os.getenv("OPENAI_API_KEY")




llm = ChatOpenAI(model="gpt-4", temperature=0.3)
