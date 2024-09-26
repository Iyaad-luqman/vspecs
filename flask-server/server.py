import face_recognition
import os
import pickle
import google.generativeai as genai
from dotenv import load_dotenv
from flask import Flask, request, jsonify
import base64
from ultralytics import YOLO
import cv2
import re
from pydub import AudioSegment
from collections import Counter
import speech_recognition as sr
app = Flask(__name__)
load_dotenv()

# Load YOLO model
model = YOLO("yolov8n.pt")  # Pretrained YOLOv8n model

# --- Face Recognition Setup ---
ENCODINGS_FILE = 'face_encodings.pkl'
known_face_encodings = []
known_face_names = []

def save_encodings():
    """Save face encodings and names to a file."""
    with open(ENCODINGS_FILE, 'wb') as f:
        pickle.dump((known_face_encodings, known_face_names), f)

def load_encodings():
    """Load face encodings and names from a file."""
    global known_face_encodings, known_face_names
    if os.path.exists(ENCODINGS_FILE):
        with open(ENCODINGS_FILE, 'rb') as f:
            known_face_encodings, known_face_names = pickle.load(f)

def upload_image_for_recognition(image_path, name):
    """Upload an image for face recognition, store the face encoding with the given name."""
    image = face_recognition.load_image_file(image_path)
    face_encodings = face_recognition.face_encodings(image)

    if len(face_encodings) == 0:
        raise ValueError("No face found in the image.")

    known_face_encodings.append(face_encodings[0])
    known_face_names.append(name)
    save_encodings()

def recognize_image(image_path):
    """Recognize faces in the provided image."""
    image = face_recognition.load_image_file(image_path)
    face_encodings = face_recognition.face_encodings(image)

    if len(face_encodings) == 0:
        return "No face found in the image."

    face_encoding = face_encodings[0]
    matches = face_recognition.compare_faces(known_face_encodings, face_encoding)
    name = "Unknown"

    if True in matches:
        first_match_index = matches.index(True)
        name = known_face_names[first_match_index]

    return name

# Load known face encodings at the start
load_encodings()

# --- Complex Scene Detection Functions ---
genai.configure(api_key=os.getenv("GEMINI_API_KEY"))
generation_config = {
    "temperature": 1,
    "top_p": 0.95,
    "top_k": 64,
    "max_output_tokens": 8192,
    "response_mime_type": "text/plain",
}
gemini_model = genai.GenerativeModel(
    model_name="gemini-1.5-pro",
    generation_config=generation_config,
)

def analyze_image(image_path, query):
    """Analyze an image using the Gemini AI model."""
    file = genai.upload_file(image_path, mime_type="image/jpeg")

    chat_session = gemini_model.start_chat(
        history=[
            {
                "role": "user",
                "parts": [
                    "I will provide images and ask you questions, explain like a blind person who can't see whatever's in front of me, stick to the question.",
                ],
            },
            {
                "role": "user",
                "parts": [
                    file,
                    query,
                ],
            },
        ]
    )

    response = chat_session.send_message(query)
    return response.text

# --- YOLO Object Detection Functions ---
def object_detection(image_path):
    """Perform object detection on an image using YOLOv8."""
    results = model.predict(image_path)
    result = results[0]
    
    output = ''
    for box in result.boxes:
        class_id = result.names[box.cls[0].item()]
        cords = box.xyxy[0].tolist()
        cords = [round(x) for x in cords]
        output += f'{class_id} at coordinates:  {cords}\n'
    
    return output

def translate_coordinates_to_positions(coordinates_str):
    """Translate coordinates into positions (left, center, right, top, middle, bottom)."""
    left_threshold = 100
    right_threshold = 300
    top_threshold = 100
    bottom_threshold = 300

    pattern = re.compile(r'(\w+) at coordinates:  \[(\d+), (\d+), (\d+), (\d+)\]')
    matches = pattern.findall(coordinates_str)

    positions = {}

    for match in matches:
        object_name, x1, y1, x2, y2 = map(int, match[1:])
        horizontal_position = 'left' if x1 < left_threshold else 'right' if x2 > right_threshold else 'center'
        vertical_position = 'top' if y1 < top_threshold else 'bottom' if y2 > bottom_threshold else 'middle'
        position = f'{horizontal_position}-{vertical_position}'

        if object_name not in positions:
            positions[object_name] = []
        positions[object_name].append(position)

    most_common_positions = {obj: Counter(pos_list).most_common(1)[0][0] for obj, pos_list in positions.items()}
    return most_common_positions

# --- Flask Routes ---
@app.route('/uploads', methods=['POST'])
def process_audio_and_image():
    """Process both audio and image files, and provide textual responses based on the image."""
    data = request.get_json()
    if 'image' not in data or 'audio' not in data:
        return jsonify({'error': 'Image and audio are required'}), 400

    # Decode the image and save it temporarily
    image_data = base64.b64decode(data['image'])
    image_path = 'uploads/temp_image.jpg'
    with open(image_path, 'wb') as f:
        f.write(image_data)
    
    # For now, we assume the audio is for processing commands or as an input placeholder.
    # You can extend this part by adding audio-to-text conversion, but we will skip it for now.
    audio_data = base64.b64decode(data['audio'])
    # Save the audio data to a temporary file
   # Save the audio data to a temporary AAC file
    aac_file_path = 'uploads/temp_audio.aac'
    with open(aac_file_path, 'wb') as f:
        f.write(audio_data)

    # Convert the AAC file to WAV format
    wav_file_path = 'uploads/temp_audio.wav'
    audio = AudioSegment.from_file(aac_file_path, format='aac')
    audio.export(wav_file_path, format='wav')

    # Initialize the recognizer
    recognizer = sr.Recognizer()

    # Load the audio file
    with sr.AudioFile(wav_file_path) as source:
        audio = recognizer.record(source)

    # Convert the audio to text
    try:
        query_from_audio = recognizer.recognize_google(audio)
        print("Transcription: " + query_from_audio)
    except sr.UnknownValueError:
        query_from_audio = "Could not understand the audio"
        print("Google Speech Recognition could not understand the audio")
    except sr.RequestError as e:
        query_from_audio = "Could not request results from Google Speech Recognition service"
        print("Could not request results from Google Speech Recognition service; {0}".format(e))


    # Simulating an audio transcript query. In a real-world scenario, you'd use audio transcription services.

    # Action classification logic based on audio query
    action = classify_action(query_from_audio)
    print(action)
    if action == 'face_rec':
        result = recognize_image(image_path)
    elif action == 'comp_scene':
        result = analyze_image(image_path, query_from_audio)
    elif action == 'obj_det':
        output = object_detection(image_path)
        translated_output = translate_coordinates_to_positions(output)
        result = ". ".join([f'{obj} is at {pos}' for obj, pos in translated_output.items()])
    else:
        result = "Unknown action."

    # Remove the temporary image file
    os.remove(image_path)
    print(result)
    return jsonify({'response': result})

def classify_action(query):
    """Classify user query as face recognition, object detection, or complex scene analysis."""
    prompt = "prompt: Classify the user query into 3 actions namely face recognition,object detection and complex scene detection. if it relates to face recognition then 'face_rec' else if it relates to object detection then 'obj_det' else if it relates to complex scene understanding, then 'comp_scene'. Just output that word and word alone"
    chat_session = gemini_model.start_chat(
        history=[
            {
                "role": "user",
                "parts": [prompt],
            },
            {
                "role": "user",
                "parts": [query],
            },
        ]
    )

    response = chat_session.send_message(query).text.strip().lower()
    return response

if __name__ == '__main__':
    app.run(debug=True, host='0.0.0.0')
