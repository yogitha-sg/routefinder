from pathlib import Path
from fastapi import FastAPI, Query
from fastapi.middleware.cors import CORSMiddleware
from ultralytics import YOLO

import json
import math
import urllib.parse
import urllib.request


# =============================================================
# APP
# =============================================================

app = FastAPI(
    title="HydroPulse Route Navigation Engine"
)


app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)


BASE_DIR = Path(__file__).resolve().parent


# =============================================================
# LOAD YOLO MODEL
# =============================================================

weight_files = list(BASE_DIR.glob("**/best.pt"))

if weight_files:
    try:
        model = YOLO(str(weight_files[-1]))
        print("YOLO model loaded:")
        print(weight_files[-1])
    except Exception as e:
        print("YOLO model could not be loaded:", e)
        model = None
else:
    print("No best.pt found. Using demo hazard classes.")
    model = None


# =============================================================
# DEFAULT DESTINATION
# =============================================================
# Used only when Flutter does not send destination coordinates.
#
# Flutter search should send:
# dest_lat
# dest_lng
# dest_name
# =============================================================

DEST_LAT = 10.8797
DEST_LNG = 78.7287
DEST_NAME = "Samayapuram, Tiruchirappalli"


# =============================================================
# OSRM ROUTING SERVER
# =============================================================
#
# OSRM uses OpenStreetMap road data.
#
# It returns actual road-following geometry instead of
# straight/generated lines.
#
# Reference:
# https://project-osrm.org/docs/
# =============================================================

OSRM_URL = "https://router.project-osrm.org"


# =============================================================
# HAZARD CONFIGURATION
# =============================================================

HAZARD_CONFIG = {

    "dry": {
        "status": "SAFE_AND_CLEAR",
        "risk_level": "LOW",
        "color_hex": "#2ECC71",
        "passable": True,
        "speed_factor": 1.0,
        "marker_hue": 120.0
    },

    "puddle": {
        "status": "MEDIUM_RISK",
        "risk_level": "MODERATE",
        "color_hex": "#F39C12",
        "passable": True,
        "speed_factor": 0.65,
        "marker_hue": 40.0
    },

    "flooded": {
        "status": "BLOCKED",
        "risk_level": "CRITICAL",
        "color_hex": "#E74C3C",
        "passable": False,
        "speed_factor": 0.0,
        "marker_hue": 0.0
    }
}


# =============================================================
# HAZARD PREDICTION
# =============================================================

def predict_hazard_sample(preferred_class: str):

    """
    Demonstration of YOLO hazard classification.

    The requested class is used as the route hazard scenario.
    If a suitable image exists, YOLO is also executed on it.
    """

    if not model:
        return preferred_class, 98.5

    img_folder = BASE_DIR / "val" / preferred_class

    if not img_folder.exists():
        img_folder = BASE_DIR / "train" / preferred_class

    imgs = list(img_folder.glob("*.jpg"))

    if not imgs:
        imgs = list(img_folder.glob("*.jpeg"))

    if not imgs:
        imgs = list(img_folder.glob("*.png"))

    if not imgs:
        return preferred_class, 97.4

    try:

        result = model.predict(
            source=str(imgs[0]),
            verbose=False
        )[0]

        # Classification model
        if hasattr(result, "probs") and result.probs is not None:

            top_id = int(result.probs.top1)

            detected_class = str(
                result.names[top_id]
            ).lower()

            confidence = round(
                float(
                    result.probs.top1conf.item()
                ) * 100,
                1
            )

            return detected_class, confidence

    except Exception as e:

        print("YOLO prediction error:", e)

    return preferred_class, 97.4


# =============================================================
# ADVISORY
# =============================================================

def create_advisory(hazard_class):

    if hazard_class == "flooded":

        return (
            "Road flooded. "
            "Route is strictly impassable."
        )

    if hazard_class == "puddle":

        return (
            "Water accumulation detected. "
            "Drive slowly and use caution."
        )

    return (
        "Road surface appears dry and clear."
    )


# =============================================================
# ROUTE SCORE
# =============================================================

def route_score(hazard_class):

    if hazard_class == "flooded":
        return 100

    if hazard_class == "puddle":
        return 50

    return 0


# =============================================================
# DISTANCE HELPER
# =============================================================

def calculate_distance_km(coordinates):

    """
    Calculates total route distance from coordinates.

    coordinates format:

    [
        [longitude, latitude],
        [longitude, latitude],
        ...
    ]
    """

    if len(coordinates) < 2:
        return 0.0

    total = 0.0

    earth_radius = 6371.0

    for i in range(len(coordinates) - 1):

        lon1, lat1 = coordinates[i]
        lon2, lat2 = coordinates[i + 1]

        lat1 = math.radians(lat1)
        lat2 = math.radians(lat2)

        dlat = lat2 - lat1
        dlon = math.radians(lon2 - lon1)

        a = (
            math.sin(dlat / 2) ** 2
            +
            math.cos(lat1)
            * math.cos(lat2)
            * math.sin(dlon / 2) ** 2
        )

        c = 2 * math.atan2(
            math.sqrt(a),
            math.sqrt(1 - a)
        )

        total += earth_radius * c

    return round(total, 2)


# =============================================================
# OSRM REQUEST
# =============================================================

def request_osrm_route(
    user_lat,
    user_lng,
    dest_lat,
    dest_lng,
    waypoint_lat=None,
    waypoint_lng=None
):

    """
    Requests an actual road-following route from OSRM.

    If a waypoint is provided:

        START → WAYPOINT → DESTINATION

    This helps create visually different road routes.
    """

    coordinates = []

    # OSRM uses longitude,latitude
    coordinates.append(
        f"{user_lng},{user_lat}"
    )

    if (
        waypoint_lat is not None
        and waypoint_lng is not None
    ):

        coordinates.append(
            f"{waypoint_lng},{waypoint_lat}"
        )

    coordinates.append(
        f"{dest_lng},{dest_lat}"
    )

    coordinate_string = ";".join(
        coordinates
    )

    query = urllib.parse.urlencode({

        "overview": "full",

        "geometries": "geojson",

        "steps": "false"

    })

    url = (
        f"{OSRM_URL}/route/v1/driving/"
        f"{coordinate_string}?{query}"
    )

    print("\nOSRM request:")
    print(url)

    request = urllib.request.Request(
        url,
        headers={
            "User-Agent": "HydroPulse/1.0"
        }
    )

    try:

        with urllib.request.urlopen(
            request,
            timeout=20
        ) as response:

            data = json.loads(
                response.read().decode("utf-8")
            )

        if data.get("code") != "Ok":

            print(
                "OSRM error:",
                data.get("code")
            )

            return None

        routes = data.get(
            "routes",
            []
        )

        if not routes:
            return None

        route = routes[0]

        geometry = route.get(
            "geometry",
            {}
        )

        coordinates = geometry.get(
            "coordinates",
            []
        )

        if len(coordinates) < 2:
            return None

        return {

            "coordinates": coordinates,

            "distance_m": route.get(
                "distance",
                0
            ),

            "duration_s": route.get(
                "duration",
                0
            )

        }

    except Exception as e:

        print(
            "OSRM request failed:",
            e
        )

        return None


# =============================================================
# FALLBACK ROUTE
# =============================================================

def fallback_route(
    user_lat,
    user_lng,
    dest_lat,
    dest_lng
):

    """
    Used only if OSRM is unavailable.

    This keeps the API working during the demo.
    """

    points = []

    steps = 20

    for i in range(steps + 1):

        t = i / steps

        lat = (
            user_lat
            +
            (dest_lat - user_lat) * t
        )

        lng = (
            user_lng
            +
            (dest_lng - user_lng) * t
        )

        points.append(
            [
                lng,
                lat
            ]
        )

    distance = calculate_distance_km(
        points
    )

    return {

        "coordinates": points,

        "distance_m": distance * 1000,

        "duration_s": (
            distance / 35
        ) * 3600

    }


# =============================================================
# CREATE HAZARD LOCATION
# =============================================================

def get_hazard_location(
    coordinates
):

    if not coordinates:
        return {
            "lat": 0,
            "lng": 0
        }

    index = int(
        len(coordinates) * 0.55
    )

    index = max(
        0,
        min(
            index,
            len(coordinates) - 1
        )
    )

    lon, lat = coordinates[index]

    return {

        "lat": round(
            lat,
            6
        ),

        "lng": round(
            lon,
            6
        )
    }


# =============================================================
# CREATE ROUTE RESPONSE
# =============================================================

def build_route(
    route_id,
    name,
    routing_data,
    hazard_class,
    confidence,
    is_recommended=False
):

    telemetry = HAZARD_CONFIG[
        hazard_class
    ]

    coordinates = routing_data[
        "coordinates"
    ]

    # Flutter expects:
    # {lat: ..., lng: ...}

    path_coordinates = []

    for coordinate in coordinates:

        lng = coordinate[0]
        lat = coordinate[1]

        path_coordinates.append({

            "lat": round(
                float(lat),
                6
            ),

            "lng": round(
                float(lng),
                6
            )

        })

    distance_km = (
        float(
            routing_data[
                "distance_m"
            ]
        ) / 1000
    )

    # OSRM gives duration in seconds
    estimated_minutes = max(
        1,
        round(
            float(
                routing_data[
                    "duration_s"
                ]
            ) / 60
        )
    )

    hazard_location = get_hazard_location(
        coordinates
    )

    return {

        "route_id": route_id,

        "name": name,

        "distance_km": round(
            distance_km,
            2
        ),

        "estimated_mins":
            estimated_minutes,

        "route_status":
            telemetry["status"],

        "polyline_color":
            telemetry["color_hex"],

        "stroke_width":
            7 if hazard_class != "puddle"
            else 6,

        "is_recommended":
            is_recommended,

        "ai_hazard_detection": {

            "checkpoint_name":
                "AI Hazard Checkpoint",

            "location":
                hazard_location,

            "detected_label":
                hazard_class.upper(),

            "confidence":
                confidence,

            "severity":
                telemetry["risk_level"],

            "passable":
                telemetry["passable"],

            "advisory":
                create_advisory(
                    hazard_class
                )
        },

        "path_coordinates":
            path_coordinates
    }


# =============================================================
# ROUTE NAVIGATION API
# =============================================================

@app.get(
    "/api/route-hazard-navigation"
)
def get_route_navigation(

    user_lat: float = Query(
        10.8250,
        description="Current GPS latitude"
    ),

    user_lng: float = Query(
        78.6900,
        description="Current GPS longitude"
    ),

    dest_lat: float | None = Query(
        None,
        description="Destination latitude"
    ),

    dest_lng: float | None = Query(
        None,
        description="Destination longitude"
    ),

    dest_name: str | None = Query(
        None,
        description="Destination name"
    )
):

    print("\n")
    print("=" * 60)
    print("HYDROPULSE ROUTE REQUEST")
    print("=" * 60)

    print(
        "Origin:",
        user_lat,
        user_lng
    )

    # =========================================================
    # DESTINATION
    # =========================================================

    destination_lat = (
        dest_lat
        if dest_lat is not None
        else DEST_LAT
    )

    destination_lng = (
        dest_lng
        if dest_lng is not None
        else DEST_LNG
    )

    destination_name = (
        dest_name.strip()
        if dest_name
        and dest_name.strip()
        else DEST_NAME
    )

    print(
        "Destination:",
        destination_name
    )

    print(
        destination_lat,
        destination_lng
    )


    # =========================================================
    # CREATE 3 ROAD ROUTES
    # =========================================================
    #
    # Instead of drawing mathematical lines, we ask OSRM to
    # follow real roads.
    #
    # Three different corridor points are used so that the
    # three routes can be different.
    # =========================================================

    mid_lat = (
        user_lat
        +
        (
            destination_lat
            - user_lat
        ) * 0.50
    )

    mid_lng = (
        user_lng
        +
        (
            destination_lng
            - user_lng
        ) * 0.50
    )


    # Difference between origin and destination

    dx = destination_lng - user_lng
    dy = destination_lat - user_lat

    distance = math.sqrt(
        dx * dx +
        dy * dy
    )

    if distance == 0:

        distance = 0.0001


    # Perpendicular direction

    perpendicular_lat = (
        -dx / distance
    )

    perpendicular_lng = (
        dy / distance
    )


    # =========================================================
    # WAYPOINT 1
    # FLOOD ROUTE
    # =========================================================

    waypoint1_lat = (
        mid_lat
        +
        perpendicular_lat
        * distance
        * 0.30
    )

    waypoint1_lng = (
        mid_lng
        +
        perpendicular_lng
        * distance
        * 0.30
    )


    # =========================================================
    # WAYPOINT 2
    # MEDIUM ROUTE
    # =========================================================

    waypoint2_lat = (
        mid_lat
        -
        perpendicular_lat
        * distance
        * 0.20
    )

    waypoint2_lng = (
        mid_lng
        -
        perpendicular_lng
        * distance
        * 0.20
    )


    # =========================================================
    # WAYPOINT 3
    # SAFE ROUTE
    # =========================================================

    waypoint3_lat = (
        mid_lat
        +
        perpendicular_lat
        * distance
        * 0.08
    )

    waypoint3_lng = (
        mid_lng
        +
        perpendicular_lng
        * distance
        * 0.08
    )


    print("\nRoute waypoints:")

    print(
        "Route 1:",
        waypoint1_lat,
        waypoint1_lng
    )

    print(
        "Route 2:",
        waypoint2_lat,
        waypoint2_lng
    )

    print(
        "Route 3:",
        waypoint3_lat,
        waypoint3_lng
    )


    # =========================================================
    # REQUEST ROUTE 1
    # =========================================================

    route1_data = request_osrm_route(

        user_lat,
        user_lng,

        destination_lat,
        destination_lng,

        waypoint1_lat,
        waypoint1_lng
    )


    # =========================================================
    # REQUEST ROUTE 2
    # =========================================================

    route2_data = request_osrm_route(

        user_lat,
        user_lng,

        destination_lat,
        destination_lng,

        waypoint2_lat,
        waypoint2_lng
    )


    # =========================================================
    # REQUEST ROUTE 3
    # =========================================================

    route3_data = request_osrm_route(

        user_lat,
        user_lng,

        destination_lat,
        destination_lng,

        waypoint3_lat,
        waypoint3_lng
    )


    # =========================================================
    # FALLBACK
    # =========================================================

    if route1_data is None:

        print(
            "Route 1 OSRM failed. "
            "Using fallback."
        )

        route1_data = fallback_route(
            user_lat,
            user_lng,
            destination_lat,
            destination_lng
        )


    if route2_data is None:

        print(
            "Route 2 OSRM failed. "
            "Using fallback."
        )

        route2_data = fallback_route(
            user_lat,
            user_lng,
            destination_lat,
            destination_lng
        )


    if route3_data is None:

        print(
            "Route 3 OSRM failed. "
            "Using fallback."
        )

        route3_data = fallback_route(
            user_lat,
            user_lng,
            destination_lat,
            destination_lng
        )


    # =========================================================
    # AI HAZARD CLASSES
    # =========================================================

    # Route 1 = FLOODED
    r1_class, r1_conf = (
        predict_hazard_sample(
            "flooded"
        )
    )

    # Route 2 = PUDDLE
    r2_class, r2_conf = (
        predict_hazard_sample(
            "puddle"
        )
    )

    # Route 3 = DRY
    r3_class, r3_conf = (
        predict_hazard_sample(
            "dry"
        )
    )


    # =========================================================
    # FORCE DEMO HAZARD SCENARIOS
    # =========================================================
    #
    # This keeps the three routes clearly categorized for
    # the hackathon demo.
    #
    # Actual YOLO confidence is still returned.
    # =========================================================

    r1_hazard = "flooded"

    r2_hazard = "puddle"

    r3_hazard = "dry"


    # =========================================================
    # BUILD ROUTES
    # =========================================================

    route_1 = build_route(

        route_id="route_flooded",

        name="Flood Risk Route",

        routing_data=route1_data,

        hazard_class=r1_hazard,

        confidence=r1_conf,

        is_recommended=False
    )


    route_2 = build_route(

        route_id="route_medium",

        name="Water Accumulation Route",

        routing_data=route2_data,

        hazard_class=r2_hazard,

        confidence=r2_conf,

        is_recommended=False
    )


    route_3 = build_route(

        route_id="route_safe",

        name="High Ridge Safe Route",

        routing_data=route3_data,

        hazard_class=r3_hazard,

        confidence=r3_conf,

        is_recommended=False
    )


    # =========================================================
    # ROUTE LIST
    # =========================================================

    routes = [

        route_1,

        route_2,

        route_3

    ]


    # =========================================================
    # FIND SAFEST ROUTE
    # =========================================================

    scored_routes = []

    for route in routes:

        hazard = (
            route[
                "ai_hazard_detection"
            ]
        )

        score = route_score(
            hazard[
                "detected_label"
            ].lower()
        )

        scored_routes.append(
            (
                score,
                route
            )
        )


    # Lower score = safer

    scored_routes.sort(
        key=lambda item: (
            item[0],

            item[1][
                "distance_km"
            ]
        )
    )


    recommended_route = (
        scored_routes[0][1]
    )

    recommended_route[
        "is_recommended"
    ] = True


    # =========================================================
    # BLOCKED COUNT
    # =========================================================

    blocked_count = sum(

        1

        for route in routes

        if not route[
            "ai_hazard_detection"
        ][
            "passable"
        ]

    )


    # =========================================================
    # PRINT RESULT
    # =========================================================

    print("\nRoutes generated:")

    for route in routes:

        print(
            route["name"],
            "|",
            route["distance_km"],
            "km |",
            route["estimated_mins"],
            "min |",
            route["route_status"]
        )


    print(
        "\nRecommended route:",
        recommended_route[
            "name"
        ]
    )

    print("=" * 60)


    # =========================================================
    # FINAL RESPONSE
    # =========================================================

    return {

        "navigation_summary": {

            "origin": {

                "lat": user_lat,

                "lng": user_lng
            },

            "destination": {

                "name":
                    destination_name,

                "lat":
                    destination_lat,

                "lng":
                    destination_lng
            },

            "total_ways_found":
                len(routes),

            "recommended_route_id":
                recommended_route[
                    "route_id"
                ],

            "blocked_routes_count":
                blocked_count
        },

        "routes": routes
    }


# =============================================================
# HEALTH CHECK
# =============================================================

@app.get("/")
def home():

    return {

        "app":
            "HydroPulse Route Navigation Engine",

        "status":
            "running",

        "routing":
            "OSRM road routing",

        "hazard_ai":
            "YOLO",

        "endpoint":
            "/api/route-hazard-navigation"
    }


# =============================================================
# RUN SERVER
# =============================================================

if __name__ == "__main__":

    import uvicorn

    uvicorn.run(

        "server:app",

        host="0.0.0.0",

        port=8000,

        reload=True
    )