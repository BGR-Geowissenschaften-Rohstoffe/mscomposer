#! /bin/bash
# remove previous installation
sudo apt purge -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin docker-ce-rootless-extras
# install apparmor first to prevent errors when starting containers
sudo apt update
sudo apt install -y apparmor
# install docker via convieniance script
curl -fsSL https://get.docker.com -o get-docker.sh
sudo sh ./get-docker.sh
# remove the script
rm ./get-docker.sh
# add docker group and add current user as well as eouser
sudo groupadd -f docker
sudo usermod -aG docker $USER
sudo usermod -aG docker eouser
# start the service
sudo systemctl enable docker.service
sudo systemctl enable containerd.service
# activate new group
newgrp docker
# pull geospatial image
docker pull rocker/geospatial:latest
# start a container
docker run --rm -it -d --name mscomposer -e PASSWORD=opendata -p 8787:8787 -v /codede:/codede -v /home/eouser:/home/rstudio rocker/geospatial:latest
# install a remote r package
#docker exec -d -it mscomposer R -e "remotes::install_github('bgr/mscomposer')"
