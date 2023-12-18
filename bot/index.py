from io import BytesIO
import json
import requests
import os
import boto3

tgkey = os.environ["BOT_TOKEN"]
database_endpoint = os.environ.get('DATABASE_ENDPOINT')
api_gateway_id = os.environ.get('API_GATEWAY_ID')
dynamodb = boto3.resource('dynamodb', endpoint_url=database_endpoint)
table = dynamodb.Table('faces_data')

face_keys = {}


def handler(event, context):
    update = json.loads(event["body"])
    message = update["message"]
    chat_id = message["chat"]["id"]

    if "text" in message:
        text = message["text"]
        if text.startswith("/getface"):
            handle_getface_command(chat_id)
        elif text.startswith("/find"):
            handle_find_command(chat_id, text)
        else:
            handle_text_response(chat_id, text)
    else:
        send_message(tgkey, chat_id, "Ошибка.")

    return {'statusCode': 200}


def handle_getface(chat_id):
    face_key, photo_url = get_annomymous_face()
    if face_key and photo_url:
        response = requests.get(photo_url)
        if response.status_code == 200:
            photo = BytesIO(response.content)
            photo.name = face_key
            print(photo_url)
            send_photo(tgkey, chat_id, photo)
            face_keys[chat_id] = face_key
        else:
            print("Ошибка при загрузке изображения")
    else:
        send_message(tgkey, chat_id, "Изображение не найдено.")


def handle_find(chat_id, text):
    name = text.split(maxsplit=1)[1] if len(text.split()) > 1 else ""
    items = find_photos_by_name(name)
    if items:
        for item in items:
            response = requests.get(item['url'])
            if response.status_code == 200:
                photo = BytesIO(response.content)
                photo.name = item['original_image_key']
                send_photo(tgkey, chat_id, photo)
            else:
                print("Ошибка при загрузке изображения")
    else:
        send_message(tgkey, chat_id, "Фотографии не найдены.")


def handle_text_response(chat_id, text):
    if chat_id in face_keys:
        save_name_to_face(face_keys[chat_id], text)
        del face_keys[chat_id]
        rep_text = "Имя сохранено"
    else:
        rep_text = "Сперва получите изображение лица /getface"
    send_message(tgkey, chat_id, rep_text)


def send_message(tgkey, chat_id, text):
    url = f"https://api.telegram.org/bot{tgkey}/sendMessage"
    params = {"chat_id": chat_id, "text": text}
    requests.get(url=url, params=params)

def get_annomymous_face():
    response = table.scan(
        FilterExpression='attribute_not_exists(person_name) or person_name = :val',
        ExpressionAttributeValues={':val': ''}
    )
    items = response.get('Items', [])
    if items:
        face = items[0]
        face_key = face['face_image_key']
        photo_url = f"https://{api_gateway_id}.apigw.yandexcloud.net/?face={face_key}"
        return face_key, photo_url
    return None, None
def save_name_to_face(face_key, name):
    table.update_item(
        Key={'face_image_key': face_key},
        UpdateExpression='SET person_name = :val',
        ExpressionAttributeValues={':val': name}
    )
    
def send_photo(tgkey, chat_id, photo):
    url = f"https://api.telegram.org/bot{tgkey}/sendPhoto"
    files = {'photo': photo}
    data = {'chat_id': chat_id}
    requests.post(url, files=files, data=data)





def find_photos_by_name(name):
    response = table.scan(
        FilterExpression='person_name = :val',
        ExpressionAttributeValues={':val': name}
    )
    items = response.get('Items', [])
    if items:
        for item in items:
            image_key = item['original_image_key']
            item["url"] = f"https://{api_gateway_id}.apigw.yandexcloud.net/original?image={image_key}"
        return items
    return None