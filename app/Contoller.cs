using System;
using Microsoft.AspNetCore.Mvc;
using Microsoft.Extensions.Configuration;
using Microsoft.Extensions.Logging;
using System.Data.SqlClient;

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
        var deploymentMethod = _configuration["DEPLOYMENT_METHOD"] ?? "Unknown";
        using (var connection = new SqlConnection(_configuration["ConnectionString"]))
        {
            try
            {
                connection.Open();
            }
            catch (Exception e)
            {
                return new OutputData
                {
                    Status = $"Couldn't open db connection: {e.Message}",
                    DeploymentMethod = deploymentMethod
                };
            }
            using (SqlCommand command = new SqlCommand("select count(*) from SalesLT.Product", connection))
            {
                try
                {
                    using (SqlDataReader reader = command.ExecuteReader())
                    {
                        reader.Read();
                        return new OutputData
                        {
                            Status = $"Connected to db, {reader.GetInt32(0)} rows found",
                            DeploymentMethod = _configuration["DEPLOYMENT_METHOD"] ?? "Unknown"
                        };
                    }
                }
                catch (Exception e)
                {
                    return new OutputData
                    {
                        Status = $"Connected to DB but no data found: {e.Message}",
                        DeploymentMethod = _configuration["DEPLOYMENT_METHOD"] ?? "Unknown"
                    };
                }
            }

        }
    }
    public class OutputData
    {
        public string CurrentDate => $"{DateTime.Now:f}";

        public string Status { get; set; }
        public string DeploymentMethod { get; set; }
    }
}