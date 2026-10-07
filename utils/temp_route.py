import urllib.request, json, urllib.parse, unicodedata

def clean(s):
    if not s: return ""
    return "".join(c for c in unicodedata.normalize('NFKD', s) if not unicodedata.combining(c)).replace('\n', ' ').upper()

def get_coords(city):
    url = 'https://api-adresse.data.gouv.fr/search/?q=' + urllib.parse.quote(city) + '&type=municipality&limit=1'
    try:
        req = urllib.request.Request(url, headers={'User-Agent': 'MagisClub/1.0'})
        data = json.loads(urllib.request.urlopen(req, timeout=5).read().decode('utf-8'))
        coords = data['features'][0]['geometry']['coordinates']
        return str(coords[0]) + ',' + str(coords[1])
    except:
        return None

def get_route():
    c1 = get_coords("RUPT")
    c2 = get_coords("FRONVILLE")
    if not c1 or not c2:
        print("ERROR_CITY")
        return
    
    url = 'http://router.project-osrm.org/route/v1/driving/{};{}?steps=true&overview=false&language=fr'.format(c1, c2)
    try:
        req = urllib.request.Request(url, headers={'User-Agent': 'MagisClub/1.0'})
        data = json.loads(urllib.request.urlopen(req, timeout=5).read().decode('utf-8'))
        route = data['routes'][0]
        print("SUMMARY|{}|{}".format(route['distance'], route['duration']))
        for step in route['legs'][0]['steps']:
            dist = step['distance']
            inst = step.get('maneuver', {}).get('instruction', '')
            print("STEP|{}|{}".format(dist, clean(inst)))
    except Exception as e:
        print("ERROR_ROUTE")

get_route()
