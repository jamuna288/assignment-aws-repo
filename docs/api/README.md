# API Documentation

## Overview

The Agent API provides intelligent recommendations for flight-related queries using a FastAPI-based service.

## Base URL

- **Production**: http://54.221.105.106
- **Load Balancer**: http://production-agent-alb-1334460343.us-east-1.elb.amazonaws.com
- **Local Development**: http://localhost:8000

## Interactive Documentation

- **Swagger UI**: `/docs`
- **ReDoc**: `/redoc`

## Endpoints

### POST /recommendation

Get intelligent agent recommendations for flight-related queries.

#### Request

```http
POST /recommendation
Content-Type: application/json

{
  "input_text": "My flight is delayed by 3 hours"
}
```

#### Response

```json
{
  "response": {
    "message": "We sincerely apologize for the flight delay. Here are your options:",
    "recommendations": [
      "Check with gate agent for updated departure time",
      "Consider rebooking on next available flight",
      "Request meal vouchers if delay exceeds 3 hours",
      "Contact customer service for accommodation if overnight delay"
    ],
    "passenger_message": "We understand your frustration and are working to get you to your destination as quickly as possible."
  }
}
```

#### Supported Query Types

1. **Flight Delays**
   - Keywords: "delay", "delayed"
   - Provides delay-specific recommendations

2. **Flight Cancellations**
   - Keywords: "cancel", "cancelled"
   - Provides cancellation assistance

3. **Weather Issues**
   - Keywords: "weather"
   - Provides weather-related guidance

4. **General Queries**
   - Default response for other flight-related questions

## Examples

### Flight Delay Query

```bash
curl -X POST "http://54.221.105.106/recommendation" \
     -H "Content-Type: application/json" \
     -d '{"input_text": "Flight delayed due to weather"}'
```

### Flight Cancellation Query

```bash
curl -X POST "http://54.221.105.106/recommendation" \
     -H "Content-Type: application/json" \
     -d '{"input_text": "My flight was cancelled"}'
```

### Weather-Related Query

```bash
curl -X POST "http://54.221.105.106/recommendation" \
     -H "Content-Type: application/json" \
     -d '{"input_text": "Weather conditions affecting my flight"}'
```

## Error Handling

The API returns standard HTTP status codes:

- `200 OK` - Successful request
- `400 Bad Request` - Invalid request format
- `422 Unprocessable Entity` - Validation error
- `500 Internal Server Error` - Server error

## Rate Limiting

Currently no rate limiting is implemented, but it's recommended for production use.

## Authentication

Currently no authentication is required, but it's recommended to implement API keys or OAuth for production use.

## Health Checks

The application provides health check endpoints:

- `/docs` - API documentation (also serves as health check)
- Direct service check via load balancer health checks
