#!/bin/bash
# Test curl file for order refund endpoint

curl -X POST "http://localhost:3000/orders/123/refund?notify=true&priority=high" \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer token123" \
  -d '{"reason": "damaged", "amount": 50.00, "notes": "Customer complaint"}'
