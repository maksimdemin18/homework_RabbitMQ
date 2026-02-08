#!/usr/bin/env python
# coding=utf-8
import pika

credentials = pika.PlainCredentials("admin", "admin")
params = pika.ConnectionParameters(
    host="192.168.56.10",
    port=5672,
    virtual_host="/",
    credentials=credentials,
)

connection = pika.BlockingConnection(params)
channel = connection.channel()

channel.queue_declare(queue="hello", durable=True)
channel.basic_publish(exchange="", routing_key="hello", body="Hello Netology! I am Demin")

connection.close()
print("Sent")
