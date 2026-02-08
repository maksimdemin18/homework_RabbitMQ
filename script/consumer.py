#!/usr/bin/env python
# coding=utf-8
import pika

credentials = pika.PlainCredentials("admin", "admin")
params = pika.ConnectionParameters(
    host="192.168.56.11",
    port=5672,
    virtual_host="/",
    credentials=credentials,
)

connection = pika.BlockingConnection(params)
channel = connection.channel()

channel.queue_declare(queue="hello", durable=True)

def callback(ch, method, properties, body):
    print(f" [x] Received {body!r}")
    ch.basic_ack(delivery_tag=method.delivery_tag)

channel.basic_consume(queue="hello", on_message_callback=callback, auto_ack=False)
print(" [*] Waiting for messages. To exit press CTRL+C")
channel.start_consuming()
