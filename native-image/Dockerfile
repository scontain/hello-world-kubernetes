ARG base_image=alpine:3.21

FROM $base_image
ENV LANG=C.UTF-8
RUN apk add --no-cache python3 py3-pip \
    && pip3 install --break-system-packages -U click
COPY /code /code
CMD [ "python3" , "/code/app.py" ]
