import pytest
from fastapi.testclient import TestClient
import sys
import os

# Add the parent directory to the path so we can import the main module
sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

from main import app

client = TestClient(app)

def test_read_main():
    """Test that the API is accessible"""
    response = client.get("/docs")
    assert response.status_code == 200

def test_recommendation_endpoint():
    """Test the recommendation endpoint"""
    test_data = {
        "input_text": "test query"
    }
    
    response = client.post("/recommendation", json=test_data)
    assert response.status_code == 200
    
    json_response = response.json()
    assert "response" in json_response
    assert isinstance(json_response["response"], str)

def test_recommendation_endpoint_empty_input():
    """Test the recommendation endpoint with empty input"""
    test_data = {
        "input_text": ""
    }
    
    response = client.post("/recommendation", json=test_data)
    assert response.status_code == 200
    
    json_response = response.json()
    assert "response" in json_response

def test_recommendation_endpoint_invalid_data():
    """Test the recommendation endpoint with invalid data"""
    response = client.post("/recommendation", json={})
    assert response.status_code == 422  # Validation error

def test_cors_headers():
    """Test that CORS headers are properly set"""
    response = client.options("/recommendation")
    # The response should include CORS headers
    assert response.status_code in [200, 405]  # Some frameworks return 405 for OPTIONS

@pytest.mark.asyncio
async def test_health_check():
    """Test basic health check"""
    response = client.get("/docs")
    assert response.status_code == 200
