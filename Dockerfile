FROM nginx:alpine

# The commit SHA is passed in by GitHub Actions so you can SEE which version is live
ARG GIT_SHA=local

COPY app/ /usr/share/nginx/html/
RUN sed -i "s/__VERSION__/${GIT_SHA}/" /usr/share/nginx/html/index.html

EXPOSE 80
