ARG base_image=alpine:3.10

FROM $base_image
ENV LANG C.UTF-8
RUN apk add --no-cache python3 \
    && ln -s /usr/bin/pip3 /usr/local/bin/pip \
    && ln -s /usr/bin/pip3 /usr/bin/pip \
    && pip3 install -U click
COPY /code /code
CMD [ "python3" , "/code/app.py" ]
