using System;
using Microsoft.AspNetCore.Mvc;
using Microsoft.Azure.Services.AppAuthentication;
using Microsoft.Extensions.Configuration;
using Microsoft.Extensions.Logging;
using System.Data.SqlClient;
using System.Collections.Generic;

[ApiController]
[Route("/")]
public class Controller : ControllerBase
{
    private readonly ILogger<Controller> _logger;
    private readonly IConfiguration _configuration;

    public Controller(ILogger<Controller> logger, IConfiguration configuration)
    {
        _logger = logger;
        _configuration = configuration;
    }

    [HttpGet]
    public OutputData Get()
    {
        using var connection = new SqlConnection(_configuration["CONNECTION_STRING"]);
        try
        {
            connection.Open();
            using var command = new SqlCommand("SELECT * FROM DemoTable", connection);
            using var reader = command.ExecuteReader();
            reader.Read();
            var data = reader[0];
            return new OutputData($"Successfully connected to the db containing info for {data}", _configuration);
        }
        catch (Exception e)
        {
            return new OutputData(e.Message, _configuration);
        }
    }
    public class OutputData
    {
        public OutputData(string status, IConfiguration configuration)
        {
            Status = status;
            DeploymentMethod = configuration["DEPLOYMENT_METHOD"] ?? "Unknown";
        }

        public string CurrentDate => $"{DateTime.Now:f}";

        public string Status { get; set; }
        public string DeploymentMethod { get; set; }
    }
}