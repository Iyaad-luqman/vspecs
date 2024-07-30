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
    except Exception as e:
        return jsonify({'error': 'Invalid image data'}), 400
    
    filename = secure_filename('uploaded_image.jpeg')
    file_path = os.path.join(app.config['UPLOAD_FOLDER'], filename)
    
    with open(file_path, 'wb') as f:
        f.write(image_bytes)
    
    # Run YOLO inference
    results = model.predict(file_path)
    result = results[0]
    
    number_of_objects =len(result.boxes)
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
    plt.savefig('recognised.jpeg', bbox_inches='tight', pad_inches=0)
    detected_objects = []
    
    recognized_image_path = os.path.join(app.config['UPLOAD_FOLDER'], 'recognized_' + filename)

    # with open(recognized_image_path, "rb") as image_file:
    #     recognized_image_base64 = base64.b64encode(image_file.read()).decode('utf-8')
    output = translate_coordinates_to_positions(output)
    grouped_output = [f'{obj} is at {pos}' for obj, pos in output.items()]
    # return jsonify({'recognized_image': recognized_image_base64, 'detected_objects': results}), 200
    return jsonify({'detected_objects': grouped_output, 'img_location':'http://192.168.1.4:7000/recognised.jpeg'}), 200

if __name__ == '__main__':
    app.run(debug=True, host='0.0.0.0')