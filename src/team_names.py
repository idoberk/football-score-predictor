"""Team-name mappings, so the same club has one name across seasons and sources."""

# Same club under two names inside Matches.csv. Only true duplicates belong here:
# Las Palmas / U.Las Palmas, Extremadura / Extremadura UD and Granada / Granada 74 look similar
# but are different clubs, so they are deliberately not mapped.
MATCHES_NAME_FIXES: dict[str, str] = {"Leonesa": "Cultural Leonesa"}

# EloRatings.csv name --> name used in Matches.csv. Verified by rating coverage, not
# by name: Each Elo club is rated densely in exactly the seasons our team played.
# Andorra CF and Leonesa are old names: From 2025-09-01 the Elo source uses the new
# names and keeps the old ones as frozen copies, which the load drops
ELO_NAME_FIXES: dict[str, str] = {
    "Tarragona": "Gimnastic",
    "Andorra CF": "Andorra",
    "Leonesa": "Cultural Leonesa",
}

FOOTBALL_DATA_TEAM_IDS: dict[int, str] = {
    263: "Alaves",
    77: "Ath Bilbao",
    78: "Ath Madrid",
    81: "Barcelona",
    90: "Betis",
    558: "Celta",
    285: "Elche",
    80: "Espanol",
    82: "Getafe",
    560: "La Coruna",
    88: "Levante",
    84: "Malaga",
    79: "Osasuna",
    86: "Real Madrid",
    5335: "Santander",
    559: "Sevilla",
    92: "Sociedad",
    95: "Valencia",
    87: "Vallecano",
    94: "Villarreal",
}
