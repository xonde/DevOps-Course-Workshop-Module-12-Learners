FROM mcr.microsoft.com/dotnet/aspnet:5.0 AS runtime
COPY out/ App/
WORKDIR /App
EXPOSE 80 
EXPOSE 443
ENTRYPOINT ["dotnet", "app.dll"]