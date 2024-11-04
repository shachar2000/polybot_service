import json

import flask
from flask import request
import os
from bot import ObjectDetectionBot
import boto3
from botocore.exceptions import ClientError
app = flask.Flask(__name__)


# TODO load TELEGRAM_TOKEN value from Secret Manager
def get_secret():

    secret_name = "Telegram_Bot_Token"
    region_name = "eu-north-1"

    # Create a Secrets Manager client
    session = boto3.session.Session()
    client = session.client(
        service_name='secretsmanager',
        region_name=region_name
    )

    try:
        get_secret_value_response = client.get_secret_value(
            SecretId=secret_name
        )
    except ClientError as e:
        # For a list of exceptions thrown, see
        # https://docs.aws.amazon.com/secretsmanager/latest/apireference/API_GetSecretValue.html
        raise e

    secret = get_secret_value_response['SecretString']
    secret = json.loads(secret)
    return secret['Telegram_Bot_Token']

TELEGRAM_TOKEN = get_secret()
TELEGRAM_APP_URL = "https://shachar.online:8443"


@app.route('/', methods=['GET'])
def index():
    return 'Ok'


@app.route(f'/{TELEGRAM_TOKEN}/', methods=['POST'])
def webhook():
    req = request.get_json()
    bot.handle_message(req['message'])
    return 'Ok'




dynamodb = boto3.resource('dynamodb', region_name='eu-north-1')

@app.route(f'/results', methods=['POST'])
def results():
    prediction_id = request.args.get('prediction_id')
    # TODO use the prediction_id to retrieve results from DynamoDB and send to the end-user
    table = dynamodb.Table('polybot-table')
    response = table.get_item(Key={'prediction_id': prediction_id})

    chat_id = int(response['Item']['chat_id'])
    objects = response['Item']['labels']
    dictrespone = {}
    for x in range(len(objects)):
        try:
            dictrespone.update({objects[x]['class']: dictrespone[objects[x]['class']]+1})
        except:
            dictrespone[objects[x]['class']] = 1
    text_results = ""
    for keys, values in dictrespone.items():
        text_results = f"{text_results}{keys}: {values}\n"

    bot.send_text(chat_id, text_results)
    return 'Ok'


@app.route(f'/loadTest/', methods=['POST'])
def load_test():
    req = request.get_json()
    bot.handle_message(req['message'])
    return 'Ok'


if __name__ == "__main__":
    bot = ObjectDetectionBot(TELEGRAM_TOKEN, TELEGRAM_APP_URL)

    app.run(host='0.0.0.0', port=8443)
