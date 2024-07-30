import base64
import os
from flask import Flask, request, jsonify
from werkzeug.utils import secure_filename
from ultralytics import YOLO
import cv2
import matplotlib.pyplot as plt
import contextlib
import io
from collections import Counter
import re
app = Flask(__name__)

# Directory to save uploaded images
UPLOAD_FOLDER = 'uploads'
if not os.path.exists(UPLOAD_FOLDER):
    os.makedirs(UPLOAD_FOLDER)

app.config['UPLOAD_FOLDER'] = UPLOAD_FOLDER

# Load YOLO model
model = YOLO("yolov8n.pt")  # pretrained YOLOv8n model
from collections import Counter
from collections import Counter
from flask import send_file
def get_unique_filename(directory, base_filename, extension):
    counter = 1
    while True:
        filename = f"{base_filename}{counter}.{extension}"
        if not os.path.exists(os.path.join(directory, filename)):
            return filename
        counter += 1
@app.route('/recognised.jpeg', methods=['GET'])
def get_recognised_image():
    try:
        return send_file('recognised.jpeg', mimetype='image/jpeg')
    except Exception as e:
        return jsonify({'error': str(e)}), 500

def translate_coordinates_to_positions(coordinates_str):
    # Define thresholds for left/right and top/bottom
    left_threshold = 100
    right_threshold = 300
    top_threshold = 100
    bottom_threshold = 300

    # Regular expression to extract object names and coordinates
    pattern = re.compile(r'(\w+) at coordinates:  \[(\d+), (\d+), (\d+), (\d+)\]')
    matches = pattern.findall(coordinates_str)

    positions = {}

    for match in matches:
        object_name, x1, y1, x2, y2 = match
        x1, y1, x2, y2 = int(x1), int(y1), int(x2), int(y2)

        # Determine horizontal position
        if x1 < left_threshold:
            horizontal_position = 'left'
        elif x2 > right_threshold:
            horizontal_position = 'right'
        else:
            horizontal_position = 'center'

        # Determine vertical position
        if y1 < top_threshold:
            vertical_position = 'top'
        elif y2 > bottom_threshold:
            vertical_position = 'bottom'
        else:
            vertical_position = 'middle'

        position = f'{horizontal_position}-{vertical_position}'

        if object_name not in positions:
            positions[object_name] = []
        positions[object_name].append(position)

    # Determine the most common position for each object
    most_common_positions = {}
    for object_name, pos_list in positions.items():
        if len(pos_list) > 3:
            most_common_positions[object_name] = f'A lot of {object_name}s'
        else:
            most_common_position = Counter(pos_list).most_common(1)[0][0]
            most_common_positions[object_name] = most_common_position

    return most_common_positions

@app.route('/uploads', methods=['POST'])
def upload_image():
    data = request.get_json()
    
    if 'image' not in data:
        return jsonify({'error': 'No image part'}), 400
    
    image_data = data['image']
    
    try:
        image_bytes = base64.b64decode(image_data)
        file_path = os.path.join(app.config['UPLOAD_FOLDER'], 'uploaded_image.jpeg')
        with open(file_path, 'wb') as f:
            f.write(image_bytes)
        
        # Run YOLO inference
        results = model.predict(file_path)
        result = results[0]
        
        number_of_objects = len(result.boxes)
        print(number_of_objects)
        output = ''
        for box in result.boxes:
            class_id = result.names[box.cls[0].item()]
            cords = box.xyxy[0].tolist()
            cords = [round(x) for x in cords]
            
            output += f'{class_id} at coordinates:  {cords}\n'
            res_plotted = result[0].plot()
        
        plt.imshow(res_plotted)
        plt.axis('off')
        recognised_filename = get_unique_filename(app.config['UPLOAD_FOLDER'], 'recognised', 'jpeg')
        recognised_filepath = os.path.join(app.config['UPLOAD_FOLDER'], recognised_filename)
        
        plt.savefig(recognised_filepath, bbox_inches='tight', pad_inches=0)
        

        output = translate_coordinates_to_positions(output)
        grouped_output = []
        for obj, pos in output.items():
            if pos.startswith('A lot of'):
                grouped_output.append(pos)
            else:
                grouped_output.append(f'{obj} is at {pos}')
        grouped_output_str = '.'.join(grouped_output)
        image_file = f'http://192.168.1.4:7000/uploads/{recognised_filename}'
        return jsonify({'text': grouped_output_str, 'image_url':image_file }), 200

    except Exception as e:
        return jsonify({'error': str(e)}), 500


if __name__ == '__main__':
    app.run(debug=True, host='0.0.0.0')