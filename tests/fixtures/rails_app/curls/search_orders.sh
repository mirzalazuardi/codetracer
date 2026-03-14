#!/bin/bash
# Test curl file for order search endpoint (GET request)

curl "http://localhost:3000/orders?status=pending&page=1&per_page=20"
