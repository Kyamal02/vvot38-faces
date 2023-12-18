import boto3
import json
import base64
import os
import requests

folder_id = os.environ.get('FOLDER_ID')
queue_url = os.environ.get('QUEUE_URL')
s3 = boto3.client('s3', endpoint_url='https://storage.yandexcloud.net')
sqs = boto3.client('sqs', endpoint_url='https://message-queue.api.cloud.yandex.net')

def handler(event, context):
    iam_token = context.token["access_token"]
    event_data = event['messages'][0]['details']
    bucket_name = event_data['bucket_id']
    file_key = event_data['object_id']

    image = s3.get_object(Bucket=bucket_name, Key=file_key)['Body'].read()
    image_base64 = base64.b64encode(image).decode('utf-8')

    faces_data = detect_faces(image_base64, folder_id, iam_token)
    faces = faces_data.get('results', [])[0].get('results', [])

    for face_result in faces:
        for face in face_result["faceDetection"].get('faces', []):
            task = {
                'image_key': file_key,
                'face_coordinates': face['boundingBox']
            }
            sqs.send_message(
                QueueUrl=queue_url,
                MessageBody=json.dumps(task)
            )

    return {
        'statusCode': 200,
        'body': 'Tasks successfully sent to the queue'
    }

def detect_faces(image_base64, folder_id, iam_token):
    url = "https://vision.api.cloud.yandex.net/vision/v1/batchAnalyze"
    headers = {
        "Content-Type": "application/json",
        "Authorization": f"Bearer {iam_token}"
    }
    body = {
        "folderId": folder_id,
        "analyze_specs": [{
            "content": image_base64,
            "features": [{"type": "FACE_DETECTION"}]
        }]
    }
    response = requests.post(url, headers=headers, data=json.dumps(body))
    return response.json()