from flask import Flask, request, jsonify
import requests

app = Flask(__name__)

# Store the directions globally to avoid multiple API requests
directions_cache = []
current_step_index = 0

def get_directions(api_key, current_location, destination):
    """
    Get directions from current_location to destination using a Maps API.
    
    :param api_key: Your Maps API key
    :param current_location: A tuple of (latitude, longitude) for the current location
    :param destination: A tuple of (latitude, longitude) for the destination
    :return: Directions as a list of steps
    """
    url = "https://maps.googleapis.com/maps/api/directions/json"
    params = {
        'origin': f"{current_location[0]},{current_location[1]}",
        'destination': f"{destination[0]},{destination[1]}",
        'key': api_key
    }
    
    response = requests.get(url, params=params)
    if response.status_code == 200:
        directions = response.json()
        steps = directions['routes'][0]['legs'][0]['steps']
        return [step['html_instructions'] for step in steps]
    else:
        return f"Error: {response.status_code}, {response.text}"

@app.route('/start_navigation', methods=['POST'])
def start_navigation():
    global directions_cache, current_step_index
    data = request.json
    api_key = data['api_key']
    current_location = tuple(data['current_location'])
    destination = tuple(data['destination'])
    
    directions_cache = get_directions(api_key, current_location, destination)
    current_step_index = 0
    
    return jsonify({"message": "Navigation started", "first_step": directions_cache[0]})

@app.route('/next_step', methods=['POST'])
def next_step():
    global current_step_index
    if current_step_index < len(directions_cache) - 1:
        current_step_index += 1
        return jsonify({"next_step": directions_cache[current_step_index]})
    else:
        return jsonify({"message": "You have arrived at your destination"})

if __name__ == '__main__':
    app.run(debug=True)
