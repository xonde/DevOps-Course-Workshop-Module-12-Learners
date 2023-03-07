# Module 12 app
A simple .NET app to show deployment status and test db connections. 

Docker image hosted at https://hub.docker.com/r/corndeldevopscourse/mod12app

To refresh the image, run the following commands:
```
$ dotnet restore
$ dotnet publish -c Release -o out
$ docker build -t corndeldevopscourse/mod12app .
$ docker push corndeldevopscourse/mod12app
```

