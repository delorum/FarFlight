extends RefCounted

# Values are persisted in v3/v4 saves; append new modes without reordering.
enum ViewMode { COCKPIT, CABIN, APRON, AIRPORT, OPERATIONS, MAIL, SHOP, HOTEL, FUEL, REPAIR, FLIGHT_HISTORY, ROUTE_HISTORY }
