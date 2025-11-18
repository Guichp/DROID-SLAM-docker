# Build image

```shell
docker build -t <my-image-name> .
```

In this case we will cal it `droid-slam`

# Run the container as defined

To run the container with an interactive shell to run any command in its system:

```shell
docker run -it --rm --name droid-slam -v .:/workspace droid-slam bash
```

`-v .:/workspace` flag binds the current working directory to the workspace directory inside the container
**Redirect GUI to host machine to see the visor!!**
**Or install VNC server?**