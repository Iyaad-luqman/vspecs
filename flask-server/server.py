import base64
from flask import Flask, request, jsonify
import os
from werkzeug.utils import secure_filename

app = Flask(__name__)

# Directory to save uploaded images
UPLOAD_FOLDER = 'uploads'
if not os.path.exists(UPLOAD_FOLDER):
    os.makedirs(UPLOAD_FOLDER)

app.config['UPLOAD_FOLDER'] = UPLOAD_FOLDER

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
        # Generate URL for the uploaded file
        file_url = f"http://192.168.1.4:7000/image.jpeg"
        
        return jsonify({'image_url': file_url, 'text': 'Image uploaded successfully for your knowledge'}), 200

if __name__ == '__main__':
    app.run(debug=True, host='0.0.0.0')