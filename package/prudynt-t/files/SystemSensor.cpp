#include "SystemSensor.hpp"
#include <iostream>
#include <sstream>
#include <stdexcept>
#include <cstdlib>
#include <memory>
#include <array>
#include <algorithm>
#include <cctype>

// For logging compatibility with prudynt-t
#ifdef LOG_DEBUG
    #define SYSTEM_SENSOR_LOG_DEBUG(msg) LOG_DEBUG("SystemSensor: " << msg)
    #define SYSTEM_SENSOR_LOG_ERROR(msg) LOG_ERROR("SystemSensor: " << msg)
    #define SYSTEM_SENSOR_LOG_INFO(msg) LOG_INFO("SystemSensor: " << msg)
#else
    #define SYSTEM_SENSOR_LOG_DEBUG(msg) std::cout << "DEBUG SystemSensor: " << msg << std::endl
    #define SYSTEM_SENSOR_LOG_ERROR(msg) std::cerr << "ERROR SystemSensor: " << msg << std::endl
    #define SYSTEM_SENSOR_LOG_INFO(msg) std::cout << "INFO SystemSensor: " << msg << std::endl
#endif

SystemSensor::SensorInfo SystemSensor::getSensorInfo() {
    SYSTEM_SENSOR_LOG_DEBUG("Getting sensor information from system");
    
    if (!isAvailable()) {
        throw std::runtime_error("System sensor script is not available");
    }
    
    try {
        auto rawData = executeSensorScript();
        auto sensorInfo = parseSensorData(rawData);
        
        SYSTEM_SENSOR_LOG_INFO("Successfully retrieved sensor info: " << sensorInfo.name 
                              << " (" << sensorInfo.width << "x" << sensorInfo.height 
                              << "@" << sensorInfo.max_fps << "fps)");
        
        return sensorInfo;
    } catch (const std::exception& e) {
        SYSTEM_SENSOR_LOG_ERROR("Failed to get sensor information: " << e.what());
        throw;
    }
}

bool SystemSensor::isAvailable() {
    // Check if sensor script exists and is executable
    int result = system("which sensor > /dev/null 2>&1");
    return (result == 0);
}

std::map<std::string, std::string> SystemSensor::executeSensorScript() {
    SYSTEM_SENSOR_LOG_DEBUG("Executing 'sensor all' command");
    
    std::map<std::string, std::string> result;
    
    // Execute sensor all command
    std::array<char, 128> buffer;
    std::string output;
    std::unique_ptr<FILE, decltype(&pclose)> pipe(popen("sensor all 2>/dev/null", "r"), pclose);
    
    if (!pipe) {
        throw std::runtime_error("Failed to execute sensor command");
    }
    
    while (fgets(buffer.data(), buffer.size(), pipe.get()) != nullptr) {
        output += buffer.data();
    }
    
    if (output.empty()) {
        throw std::runtime_error("No output from sensor command");
    }
    
    SYSTEM_SENSOR_LOG_DEBUG("Sensor command output received");
    
    // Parse output line by line
    std::istringstream stream(output);
    std::string line;
    
    while (std::getline(stream, line)) {
        // Skip empty lines
        if (line.empty()) continue;
        
        // Find the colon separator
        size_t colonPos = line.find(':');
        if (colonPos == std::string::npos) continue;
        
        // Extract key and value
        std::string key = line.substr(0, colonPos);
        std::string value = line.substr(colonPos + 1);
        
        // Trim whitespace
        key.erase(0, key.find_first_not_of(" \t"));
        key.erase(key.find_last_not_of(" \t") + 1);
        value.erase(0, value.find_first_not_of(" \t"));
        value.erase(value.find_last_not_of(" \t") + 1);
        
        if (!key.empty() && !value.empty()) {
            result[key] = value;
            SYSTEM_SENSOR_LOG_DEBUG("Parsed: " << key << " = " << value);
        }
    }
    
    if (result.empty()) {
        throw std::runtime_error("Failed to parse sensor command output");
    }
    
    return result;
}

SystemSensor::SensorInfo SystemSensor::parseSensorData(const std::map<std::string, std::string>& rawData) {
    SensorInfo info;
    
    // Parse each field with error handling
    try {
        // Required fields
        if (rawData.find("name") != rawData.end()) {
            info.name = rawData.at("name");
        } else {
            throw std::runtime_error("Missing sensor name");
        }
        
        if (rawData.find("width") != rawData.end()) {
            info.width = std::stoi(rawData.at("width"));
        }
        
        if (rawData.find("height") != rawData.end()) {
            info.height = std::stoi(rawData.at("height"));
        }
        
        if (rawData.find("max_fps") != rawData.end()) {
            info.max_fps = std::stoi(rawData.at("max_fps"));
            info.fps = info.max_fps; // Use max_fps as default fps
        }
        
        // Optional fields
        if (rawData.find("chip_id") != rawData.end()) {
            info.chip_id = rawData.at("chip_id");
        }
        
        if (rawData.find("i2c_addr") != rawData.end()) {
            info.i2c_addr = rawData.at("i2c_addr");
            info.i2c_address = parseHexString(info.i2c_addr);
        }
        
        if (rawData.find("min_fps") != rawData.end()) {
            info.min_fps = std::stoi(rawData.at("min_fps"));
        }
        
        if (rawData.find("version") != rawData.end()) {
            info.version = rawData.at("version");
        }
        
    } catch (const std::exception& e) {
        throw std::runtime_error("Failed to parse sensor data: " + std::string(e.what()));
    }
    
    return info;
}

unsigned int SystemSensor::parseHexString(const std::string& hexStr) {
    if (hexStr.empty()) {
        return 0;
    }
    
    try {
        // Handle both "0x37" and "37" formats
        if (hexStr.substr(0, 2) == "0x" || hexStr.substr(0, 2) == "0X") {
            return static_cast<unsigned int>(std::stoul(hexStr, nullptr, 16));
        } else {
            return static_cast<unsigned int>(std::stoul(hexStr, nullptr, 16));
        }
    } catch (const std::exception& e) {
        SYSTEM_SENSOR_LOG_ERROR("Failed to parse hex string '" << hexStr << "': " << e.what());
        return 0;
    }
}
