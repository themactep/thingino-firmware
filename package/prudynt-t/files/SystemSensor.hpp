#ifndef SYSTEM_SENSOR_HPP
#define SYSTEM_SENSOR_HPP

#include <string>

/**
 * SystemSensor - Interface to thingino system sensor information
 *
 * Provides access to sensor information via /proc/jz/sensor/ filesystem
 * instead of relying on configuration files. This ensures single source
 * of truth for sensor data directly from the sensor driver.
 */
class SystemSensor {
public:
    struct SensorInfo {
        std::string name;           // Sensor model name (e.g., "gc2083")
        std::string chip_id;        // Chip ID (e.g., "0x2083")
        std::string i2c_addr;       // I2C address (e.g., "0x37")
        int width;                  // Native width (e.g., 1920)
        int height;                 // Native height (e.g., 1080)
        int min_fps;                // Minimum FPS (e.g., 5)
        int max_fps;                // Maximum FPS (e.g., 30)
        std::string version;        // Sensor version (e.g., "H20220228a")

        // Additional proc fields for compatibility
        int i2c_bus;                // I2C bus number
        int boot;                   // Boot parameter
        int mclk;                   // MCLK setting
        int video_interface;        // Video interface type
        int reset_gpio;             // Reset GPIO pin

        // Derived values for compatibility
        unsigned int i2c_address;   // Parsed I2C address as uint
        int fps;                    // Default FPS (use max_fps)

        // Constructor with defaults
        SensorInfo() : width(1920), height(1080), min_fps(5), max_fps(30),
                      i2c_bus(0), boot(0), mclk(1), video_interface(0), reset_gpio(91),
                      i2c_address(0x37), fps(25) {}
    };

    /**
     * Get comprehensive sensor information from /proc/jz/sensor/
     * @return SensorInfo structure with all sensor data
     * @throws std::runtime_error if sensor information cannot be retrieved
     */
    static SensorInfo getSensorInfo();

    /**
     * Check if /proc/jz/sensor/ directory is available
     * @return true if sensor proc filesystem is accessible
     */
    static bool isAvailable();

private:
    static const std::string SENSOR_PROC_DIR;

    /**
     * Read string value from proc file
     * @param filename Filename in /proc/jz/sensor/
     * @return File content as string, empty if file doesn't exist
     */
    static std::string readProcString(const std::string& filename);

    /**
     * Read integer value from proc file
     * @param filename Filename in /proc/jz/sensor/
     * @param defaultValue Default value if file doesn't exist or parse fails
     * @return Parsed integer value or default
     */
    static int readProcInt(const std::string& filename, int defaultValue = 0);

    /**
     * Convert hex string to unsigned int
     * @param hexStr Hex string (e.g., "0x37")
     * @return Parsed unsigned integer value
     */
    static unsigned int parseHexString(const std::string& hexStr);
};

#endif // SYSTEM_SENSOR_HPP
