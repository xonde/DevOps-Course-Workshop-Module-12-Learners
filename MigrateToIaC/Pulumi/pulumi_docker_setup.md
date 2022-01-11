# Run Pulumi in Docker

* Start the container

```bash
# Start and leave running
docker run -td -v Pulumi:/pulumi --name pulumi corndeldevopscourse/pulumi-starter
```

* Install the "Docker" and "Remote - Containers" VSCode extensions
* In VSCode bring up the Command Palette (ctrl + shift + P or View -> Command Palette...) and run the "Remote-Containers: Attach To Running Container" command
* Attach to the "pulumi" container (this will take a minute)
* Open the `/pulumi` folder
* Open a terminal within VSCode and run `az login` and follow the instructions
  * Once you're signed in make sure "Softwire DevOps Academy" is the default subscription in `az account list`
* Now you're ready to `pulumi import` your resource group, return to the [workshop instructions](instructions.md)

Note that your work is stored in a named volume ("Pulumi").
