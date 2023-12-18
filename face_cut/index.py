import json
import boto3
import random
import string
import ydb
from PIL import Image
from io import BytesIO
import os

s3_client = boto3.client('s3', endpoint_url='https://storage.yandexcloud.net')
database_endpoint = os.environ.get('DATABASE_ENDPOINT')
ydb_docapi_client = boto3.resource('dynamodb', endpoint_url = database_endpoint)
source_bucket_id = os.environ.get('SOURCE_BUCKET_ID')
target_bucket_id = os.environ.get('TARGET_BUCKET_ID')

def handler(event, context):
    body = json.loads(event['messages'][0]['details']['message']["body"])
    image_key = body['image_key']
    face_coords = body['face_coordinates']['vertices']

    image_data = s3_client.get_object(Bucket=source_bucket_id, Key=image_key)
    image = Image.open(BytesIO(image_data['Body'].read()))

    left = int(face_coords[0]['x'])
    upper = int(face_coords[0]['y'])
    right = int(face_coords[2]['x'])
    lower = int(face_coords[2]['y'])
    cropped_face = image.crop((left, upper, right, lower))

    random_key = ''.join(random.choices(string.ascii_letters + string.digits, k=10)) + '.jpg'
    face_buffer = BytesIO()
    cropped_face.save(face_buffer, 'JPEG')
    face_buffer.seek(0)
    s3_client.put_object(Bucket=target_bucket_id, Key=random_key, Body=face_buffer)

    item = {
        "original_image_key": image_key,
        "face_image_key": random_key
    }
    save_to_ydb(item)

    return {
        'statusCode': 200,
        'body': json.dumps('Face cut and saved successfully')
    }


def save_to_ydb(item):
    try:
        table = ydb_docapi_client.Table('faces_data')
        table.load()
        table.put_item(Item = item)
        return table
    except:
        table = create_table()
        table.put_item(Item = item)


def create_table():
    table = ydb_docapi_client.create_table(
        TableName = 'faces_data',
        KeySchema = [
            {
                'AttributeName': 'face_image_key',
                'KeyType': 'HASH'
            }
        ],
        AttributeDefinitions = [
            {
                'AttributeName': 'original_image_key',
                'AttributeType': 'S'
            },
            {
                'AttributeName': 'face_image_key',
                'AttributeType': 'S'
            }
        ]
    )
    return table