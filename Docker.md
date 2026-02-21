# Build image

```shell
docker build -t <my-image-name> .
```

In this case we will cal it `droid-slam`

# Run the container as defined

To run the container with an interactive shell to run any command in its system:

```shell
docker run -it --rm \
    -p 6080:6080 \
    -p 5901:5901 \
    -e VNC_PW=1234 \
    -e USER=root \
    -v .:/workspace \
    --name droid-slam \
    droid-slam bash
```

`-v .:/workspace` flag binds the current working directory to the workspace directory inside the container
**Redirect GUI to host machine to see the visor!!**
**Or install VNC server?**