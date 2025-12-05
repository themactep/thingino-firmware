/*
 * Thingino BLE GATT Server - Improv WiFi Provisioning
 *
 * This implements the Improv WiFi BLE standard using libble++
 * for WiFi provisioning on Thingino devices.
 *
 */

#include <blepp/blegattserver.h>
#include <blepp/gatt_services.h>
#include <blepp/logging.h>
#include <iostream>
#include <cstring>
#include <cstdio>
#include <cstdlib>
#include <cstdarg>
#include <unistd.h>
#include <csignal>
#include <thread>
#include <chrono>
#include <atomic>
#include <mutex>

#include "improv/improv.h"

using namespace BLEPP;

// Thingino custom commands (extensions to standard Improv)
namespace improv {
    enum ThingingoCommand : uint8_t {
        SET_HOSTNAME = 0x10,
        SET_ROOT_PASSWORD = 0x11,
        SET_TIMEZONE = 0x12,
    };
}

/*******************************************************************************
 * Global State
 ******************************************************************************/

static std::atomic<bool> g_running(true);
static std::atomic<improv::State> g_current_state(improv::STATE_AUTHORIZED);
static std::atomic<improv::Error> g_current_error(improv::ERROR_NONE);
static std::vector<uint8_t> g_rpc_result_data;
static std::mutex g_rpc_result_mutex;

static BLEGATTServer* g_server = nullptr;
static uint16_t g_conn_handle = 0;
static bool g_force_mode = false;

// Characteristic handles for notifications
static uint16_t g_state_handle = 0;
static uint16_t g_error_handle = 0;
static uint16_t g_rpc_result_handle = 0;

// Device info
static std::string g_device_name = "Thingino";
static std::string g_firmware_version = "1.0.0";
static std::string g_hardware_version = "T31";
static std::string g_device_hostname = "thingino";
static std::string g_ble_device_name = "thingino-setup";

/*******************************************************************************
 * Utility Functions
 ******************************************************************************/

static void log_printf(const char* fmt, ...) {
    va_list args;
    va_start(args, fmt);
    vprintf(fmt, args);
    va_end(args);
    fflush(stdout);
}

static std::string get_hostname() {
    char line[256];

    // First try fw_printenv hostname
    FILE* fp = popen("fw_printenv hostname 2>/dev/null", "r");
    if (fp) {
        if (fgets(line, sizeof(line), fp)) {
            char* equals = strchr(line, '=');
            if (equals && strlen(equals + 1) > 0) {
                char* newline = strchr(equals + 1, '\n');
                if (newline) *newline = '\0';
                std::string hostname = equals + 1;
                pclose(fp);
                if (!hostname.empty()) {
                    return hostname;
                }
            }
        }
        pclose(fp);
    }

    // Fall back to hostname command
    fp = popen("hostname 2>/dev/null", "r");
    if (fp) {
        if (fgets(line, sizeof(line), fp)) {
            char* newline = strchr(line, '\n');
            if (newline) *newline = '\0';
            std::string hostname = line;
            pclose(fp);
            if (!hostname.empty()) {
                return hostname;
            }
        }
        pclose(fp);
    }

    return "thingino";
}

static bool check_wifi_connected() {
    FILE* fp = popen("ip addr show wlan0 2>/dev/null | grep 'inet ' | awk '{print $2}'", "r");
    if (!fp) return false;
    
    char line[256];
    bool has_ip = false;
    if (fgets(line, sizeof(line), fp) && strlen(line) > 3) {
        has_ip = true;
        log_printf("[WIFI] Connected with IP: %s", line);
    }
    pclose(fp);
    return has_ip;
}

static bool check_provisioned() {
    FILE* fp = popen("fw_printenv wlan_ssid 2>/dev/null", "r");
    if (!fp) return false;
    
    char line[256];
    bool has_ssid = false;
    if (fgets(line, sizeof(line), fp) && line[0] != '\0') {
        line[strcspn(line, "\n")] = '\0';
        char* equals = strchr(line, '=');
        if (equals && strlen(equals + 1) > 0) {
            has_ssid = true;
            log_printf("[PROVISION-CHECK] Found WiFi SSID: '%s'\n", equals + 1);
        }
    }
    pclose(fp);
    return has_ssid;
}

/*******************************************************************************
 * State Management
 ******************************************************************************/

static void update_advertising_data() {
    // Update advertising service data according to Improv WiFi v2.0 spec
    // The service data must be updated when state changes
    if (!g_server) return;

    log_printf("[IMPROV] Updating advertising service data with state: 0x%02x\n",
               (int)g_current_state.load());

    // Stop current advertising
    g_server->stop_advertising();

    // Setup new advertising with updated state
    AdvertisingParams adv_params;
    adv_params.device_name = g_ble_device_name;
    adv_params.service_uuids = {UUID(improv::SERVICE_UUID)};
    adv_params.min_interval_ms = 100;
    adv_params.max_interval_ms = 100;

    // Add Improv WiFi v2.0 service data with current state
    adv_params.service_data_uuid16 = 0x4677;
    adv_params.service_data = {
        (uint8_t)g_current_state.load(),    // Byte 1: Current state
        improv::CAPABILITY_IDENTIFY,        // Byte 2: Capabilities
        0, 0, 0, 0                          // Bytes 3-6: Reserved
    };

    // Restart advertising
    int rc = g_server->start_advertising(adv_params);
    if (rc != 0) {
        log_printf("[IMPROV] ERROR: Failed to restart advertising: %d\n", rc);
    }
}

static void set_state(improv::State new_state) {
    if (g_current_state != new_state) {
        g_current_state = new_state;
        log_printf("[IMPROV] State changed to: 0x%02x\n", (int)new_state);

        // Notify connected clients
        if (g_server && g_conn_handle && g_state_handle) {
            std::vector<uint8_t> data = {(uint8_t)new_state};
            g_server->notify(g_conn_handle, g_state_handle, data);
        }

        // Update advertising data per Improv WiFi v2.0 spec
        update_advertising_data();
    }
}

static void set_error(improv::Error new_error) {
    if (g_current_error != new_error) {
        g_current_error = new_error;
        log_printf("[IMPROV] Error set to: 0x%02x\n", (int)new_error);

        if (g_server && g_conn_handle && g_error_handle) {
            std::vector<uint8_t> data = {(uint8_t)new_error};
            g_server->notify(g_conn_handle, g_error_handle, data);
        }
    }
}

static void send_rpc_result(improv::Command command, const std::vector<std::string>& strings) {
    std::vector<uint8_t> response = improv::build_rpc_response(command, strings, true);

    {
        std::lock_guard<std::mutex> lock(g_rpc_result_mutex);
        g_rpc_result_data = response;
    }

    log_printf("[IMPROV] Sending RPC result for command 0x%02x, size: %zu\n", (int)command, response.size());

    if (g_server && g_conn_handle && g_rpc_result_handle) {
        g_server->notify(g_conn_handle, g_rpc_result_handle, response);
    }
}

/*******************************************************************************
 * WiFi Provisioning
 ******************************************************************************/

static void provision_wifi(const char* ssid, const char* password) {
    if (!ssid) {
        log_printf("[WIFI] NULL SSID\n");
        set_state(improv::STATE_AUTHORIZED);
        set_error(improv::ERROR_UNABLE_TO_CONNECT);
        return;
    }

    log_printf("[WIFI] Provisioning: %s\n", ssid);
    set_state(improv::STATE_PROVISIONING);

    char cmd[512];
    snprintf(cmd, sizeof(cmd), "fw_setenv wlan_ssid \"%s\" 2>/dev/null", ssid);
    system(cmd);

    if (password && strlen(password) > 0) {
        snprintf(cmd, sizeof(cmd), "fw_setenv wlan_pass \"%s\" 2>/dev/null", password);
    } else {
        snprintf(cmd, sizeof(cmd), "fw_setenv wlan_pass \"\" 2>/dev/null");
    }
    system(cmd);

    std::string url = "http://" + g_device_hostname + ".local";
    send_rpc_result(improv::WIFI_SETTINGS, {url});

    log_printf("[WIFI] WiFi credentials saved - triggering reboot in 10 seconds...\n");
    set_state(improv::STATE_PROVISIONED);
    set_error(improv::ERROR_NONE);

    // Reboot after 10 seconds to apply WiFi settings but allow time to read response
    std::thread([]() {
        for (int i = 10; i > 0; i--) {
            log_printf("[WIFI] Rebooting in %d seconds...\n", i);
            std::this_thread::sleep_for(std::chrono::seconds(1));
        }
        log_printf("[IMPROV] Provisioning complete - rebooting now!\n");
        sync();
        system("reboot");
    }).detach();
}

/*******************************************************************************
 * RPC Command Handlers
 ******************************************************************************/

static void handle_wifi_settings(const improv::ImprovCommand& cmd) {
    log_printf("[IMPROV] WiFi Settings received\n");
    log_printf("[IMPROV]   SSID: %s\n", cmd.ssid.c_str());
    log_printf("[IMPROV]   Password length: %zu\n", cmd.password.length());

    if (g_current_state != improv::STATE_AUTHORIZED) {
        log_printf("[IMPROV] ERROR: Not authorized\n");
        set_error(improv::ERROR_NOT_AUTHORIZED);
        return;
    }

    provision_wifi(cmd.ssid.c_str(), cmd.password.c_str());
}

static void handle_identify() {
    log_printf("[IMPROV] Identify command received\n");
    system("iac -f /usr/share/sounds/th-chime_1.pcm 2>/dev/null &");
    send_rpc_result(improv::IDENTIFY, {});
}

static void handle_get_device_info() {
    log_printf("[IMPROV] Get Device Info command received\n");
    send_rpc_result(improv::GET_DEVICE_INFO, {
        g_firmware_version,
        g_hardware_version,
        g_device_name
    });
}

static void handle_set_hostname(const std::string& hostname) {
    log_printf("[IMPROV] Set Hostname: %s\n", hostname.c_str());

    if (hostname.empty()) {
        set_error(improv::ERROR_INVALID_RPC);
        send_rpc_result((improv::Command)improv::SET_HOSTNAME, {"ERROR"});
        return;
    }

    FILE* fp = fopen("/etc/hostname", "w");
    if (fp) {
        fprintf(fp, "%s\n", hostname.c_str());
        fclose(fp);
    }

    char cmd_buf[256];
    snprintf(cmd_buf, sizeof(cmd_buf), "fw_setenv hostname \"%s\" 2>/dev/null", hostname.c_str());
    system(cmd_buf);

    snprintf(cmd_buf, sizeof(cmd_buf), "hostname %s", hostname.c_str());
    system(cmd_buf);

    send_rpc_result((improv::Command)improv::SET_HOSTNAME, {"OK"});
}

static void handle_set_root_password(const std::string& password) {
    log_printf("[IMPROV] Set Root Password command received\n");

    if (password.empty()) {
        set_error(improv::ERROR_INVALID_RPC);
        send_rpc_result((improv::Command)improv::SET_ROOT_PASSWORD, {"ERROR"});
        return;
    }

    FILE* fp = popen("chpasswd -c sha512", "w");
    if (fp) {
        fprintf(fp, "root:%s\n", password.c_str());
        int rc = pclose(fp);
        send_rpc_result((improv::Command)improv::SET_ROOT_PASSWORD, {rc == 0 ? "OK" : "ERROR"});
    }
}

static void handle_set_timezone(const std::string& timezone) {
    log_printf("[IMPROV] Set Timezone: %s\n", timezone.c_str());

    if (timezone.empty()) {
        set_error(improv::ERROR_INVALID_RPC);
        send_rpc_result((improv::Command)improv::SET_TIMEZONE, {"ERROR"});
        return;
    }

    FILE* fp = fopen("/etc/timezone", "w");
    if (fp) {
        fprintf(fp, "%s\n", timezone.c_str());
        fclose(fp);
        send_rpc_result((improv::Command)improv::SET_TIMEZONE, {"OK"});
    } else {
        send_rpc_result((improv::Command)improv::SET_TIMEZONE, {"ERROR"});
    }
}

static void handle_rpc_command(const std::vector<uint8_t>& data) {
    log_printf("[IMPROV] RPC Command received, length: %zu\n", data.size());

    improv::ImprovCommand cmd = improv::parse_improv_data(data, true);

    if (cmd.command == improv::BAD_CHECKSUM) {
        log_printf("[IMPROV] ERROR: Bad checksum\n");
        set_error(improv::ERROR_INVALID_RPC);
        return;
    }

    if (cmd.command == improv::UNKNOWN) {
        log_printf("[IMPROV] ERROR: Unknown command\n");
        set_error(improv::ERROR_UNKNOWN_RPC);
        return;
    }

    log_printf("[IMPROV] Command: 0x%02x\n", (int)cmd.command);

    // Handle standard Improv commands
    switch (cmd.command) {
        case improv::WIFI_SETTINGS:
            handle_wifi_settings(cmd);
            break;
        case improv::IDENTIFY:
            handle_identify();
            break;
        case improv::GET_DEVICE_INFO:
            handle_get_device_info();
            break;
        default:
            // Check for Thingino custom commands
            uint8_t cmd_byte = (uint8_t)cmd.command;
            if (cmd_byte == improv::SET_HOSTNAME || cmd_byte == improv::SET_ROOT_PASSWORD || cmd_byte == improv::SET_TIMEZONE) {
                // Parse custom command data (single string parameter)
                if (data.size() < 3) {
                    set_error(improv::ERROR_INVALID_RPC);
                    return;
                }

                uint8_t str_length = data[2];
                if (data.size() < 3 + str_length) {
                    set_error(improv::ERROR_INVALID_RPC);
                    return;
                }

                std::string param(data.begin() + 3, data.begin() + 3 + str_length);

                if (cmd_byte == improv::SET_HOSTNAME) {
                    handle_set_hostname(param);
                } else if (cmd_byte == improv::SET_ROOT_PASSWORD) {
                    handle_set_root_password(param);
                } else if (cmd_byte == improv::SET_TIMEZONE) {
                    handle_set_timezone(param);
                }
            } else {
                log_printf("[IMPROV] ERROR: Unsupported command: 0x%02x\n", cmd_byte);
                set_error(improv::ERROR_UNKNOWN_RPC);
            }
            break;
    }
}

/*******************************************************************************
 * GATT Characteristic Callbacks
 ******************************************************************************/

static int current_state_cb(uint16_t conn_handle, ATTAccessOp op, uint16_t offset, 
                           std::vector<uint8_t>& data) {
    if (op == ATTAccessOp::READ_CHR) {
        data = {(uint8_t)g_current_state.load()};
        return 0;
    }
    return BLE_ATT_ERR_READ_NOT_PERMITTED;
}

static int error_state_cb(uint16_t conn_handle, ATTAccessOp op, uint16_t offset, 
                         std::vector<uint8_t>& data) {
    if (op == ATTAccessOp::READ_CHR) {
        data = {(uint8_t)g_current_error.load()};
        return 0;
    }
    return BLE_ATT_ERR_READ_NOT_PERMITTED;
}

static int rpc_command_cb(uint16_t conn_handle, ATTAccessOp op, uint16_t offset, 
                         std::vector<uint8_t>& data) {
    if (op == ATTAccessOp::WRITE_CHR) {
        handle_rpc_command(data);
        return 0;
    }
    return BLE_ATT_ERR_WRITE_NOT_PERMITTED;
}

static int rpc_result_cb(uint16_t conn_handle, ATTAccessOp op, uint16_t offset, 
                        std::vector<uint8_t>& data) {
    if (op == ATTAccessOp::READ_CHR) {
        std::lock_guard<std::mutex> lock(g_rpc_result_mutex);
        data = g_rpc_result_data;
        return 0;
    }
    return BLE_ATT_ERR_READ_NOT_PERMITTED;
}

static int capabilities_cb(uint16_t conn_handle, ATTAccessOp op, uint16_t offset,
                          std::vector<uint8_t>& data) {
    if (op == ATTAccessOp::READ_CHR) {
        data = {improv::CAPABILITY_IDENTIFY};
        return 0;
    }
    return BLE_ATT_ERR_READ_NOT_PERMITTED;
}

/*******************************************************************************
 * Service Setup
 ******************************************************************************/

static GATTServiceDef create_improv_service() {
    UUID improv_service_uuid = UUID(improv::SERVICE_UUID);
    UUID current_state_uuid = UUID(improv::STATUS_UUID);
    UUID error_state_uuid = UUID(improv::ERROR_UUID);
    UUID rpc_command_uuid = UUID(improv::RPC_COMMAND_UUID);
    UUID rpc_result_uuid = UUID(improv::RPC_RESULT_UUID);
    UUID capabilities_uuid = UUID(improv::CAPABILITIES_UUID);

    GATTServiceDef service(GATTServiceType::PRIMARY, improv_service_uuid);
    
    // Current State (Read + Notify)
    auto& state_char = service.add_characteristic(current_state_uuid, 
        GATT_CHR_F_READ | GATT_CHR_F_NOTIFY, current_state_cb);
    state_char.val_handle_ptr = &g_state_handle;
    
    // Error State (Read + Notify)
    auto& error_char = service.add_characteristic(error_state_uuid, 
        GATT_CHR_F_READ | GATT_CHR_F_NOTIFY, error_state_cb);
    error_char.val_handle_ptr = &g_error_handle;
    
    // RPC Command (Write only)
    service.add_characteristic(rpc_command_uuid, GATT_CHR_F_WRITE | GATT_CHR_F_WRITE_NO_RSP, rpc_command_cb);
    
    // RPC Result (Read + Notify)
    auto& result_char = service.add_characteristic(rpc_result_uuid, 
        GATT_CHR_F_READ | GATT_CHR_F_NOTIFY, rpc_result_cb);
    result_char.val_handle_ptr = &g_rpc_result_handle;
    
    // Capabilities (Read only)
    service.add_characteristic(capabilities_uuid, GATT_CHR_F_READ, capabilities_cb);
    
    return service;
}

/*******************************************************************************
 * Signal Handler
 ******************************************************************************/

static void signal_handler(int sig) {
    log_printf("\n[MAIN] Caught signal %d, shutting down...\n", sig);
    g_running = false;
    if (g_server) {
        g_server->stop();
    }
}

/*******************************************************************************
 * Main
 ******************************************************************************/

int main(int argc, char* argv[]) {
    // Set libble++ log level to Debug for detailed output
    BLEPP::log_level = BLEPP::Debug;

    // Parse command line arguments
    for (int i = 1; i < argc; i++) {
        if (strcmp(argv[i], "-f") == 0) {
            g_force_mode = true;
            log_printf("[MAIN] Force mode enabled\n");
        }
    }

    // Check provisioning status
    if (!g_force_mode && check_provisioned()) {
        log_printf("[MAIN] ===============================================\n");
        log_printf("[MAIN] *** DEVICE ALREADY PROVISIONED - EXITING ***\n");
        log_printf("[MAIN] *** Use -f flag to force BLE service startup ***\n");
        log_printf("[MAIN] ===============================================\n");
        return 0;
    }
    
    // Get hostname for BLE name
    g_device_hostname = get_hostname();
    g_ble_device_name = g_device_hostname + "-setup";
    
    log_printf("========================================\n");
    log_printf("===  IMPROV WIFI SERVICE v1.0       ===\n");
    log_printf("===  libble++ Implementation        ===\n");
    log_printf("========================================\n");
    log_printf("[MAIN] BLE device name: %s\n", g_ble_device_name.c_str());
    log_printf("[MAIN] Redirect URL: http://%s.local\n", g_device_hostname.c_str());
    
    // Create server transport
    std::unique_ptr<BLETransport> transport(create_server_transport());
    if (!transport) {
        log_printf("[MAIN] ERROR: Failed to create BLE transport\n");
        return 1;
    }
    
    // Create GATT server
    g_server = new BLEGATTServer(std::move(transport));
    
    // Register Improv WiFi service
    std::vector<GATTServiceDef> services;
    services.push_back(create_improv_service());
    
    int rc = g_server->register_services(services);
    if (rc != 0) {
        log_printf("[MAIN] ERROR: Failed to register services: %d\n", rc);
        delete g_server;
        return 1;
    }
    
    log_printf("[MAIN] Improv WiFi service registered\n");
    log_printf("[MAIN] - State Handle: %d\n", g_state_handle);
    log_printf("[MAIN] - Error Handle: %d\n", g_error_handle);
    log_printf("[MAIN] - RPC Result Handle: %d\n", g_rpc_result_handle);
    
    // Setup advertising with Improv WiFi v2.0 service data
    AdvertisingParams adv_params;
    adv_params.device_name = g_ble_device_name;
    adv_params.service_uuids = {UUID(improv::SERVICE_UUID)};
    adv_params.min_interval_ms = 100;
    adv_params.max_interval_ms = 100;

    // Add Improv WiFi v2.0 service data
    // Service Data UUID: 0x4677 (00004677-0000-1000-8000-00805f9b34fb)
    // Format: [Current State][Capabilities][Reserved 0][Reserved 0][Reserved 0][Reserved 0]
    adv_params.service_data_uuid16 = 0x4677;
    adv_params.service_data = {
        (uint8_t)g_current_state.load(),    // Byte 1: Current state
        improv::CAPABILITY_IDENTIFY,        // Byte 2: Capabilities
        0, 0, 0, 0                          // Bytes 3-6: Reserved
    };
    
    rc = g_server->start_advertising(adv_params);
    if (rc != 0) {
        log_printf("[MAIN] ERROR: Failed to start advertising: %d\n", rc);
        delete g_server;
        return 1;
    }
    
    log_printf("[MAIN] *** ADVERTISING STARTED ***\n");
    log_printf("[MAIN] Device visible as '%s'\n", g_ble_device_name.c_str());
    
    // Setup callbacks
    g_server->on_connected = [](uint16_t conn_handle, const std::string& peer_addr) {
        g_conn_handle = conn_handle;
        log_printf("[MAIN] Client connected: handle=%d, addr=%s\n", conn_handle, peer_addr.c_str());
    };
    
    g_server->on_disconnected = [](uint16_t conn_handle) {
        log_printf("[MAIN] Client disconnected: handle=%d\n", conn_handle);
        g_conn_handle = 0;
    };
    
    // Setup signal handlers
    signal(SIGINT, signal_handler);
    signal(SIGTERM, signal_handler);
    
    // Run server event loop
    log_printf("[MAIN] Starting event loop...\n");
    rc = g_server->run();
    
    // Cleanup
    log_printf("[MAIN] Server stopped\n");
    delete g_server;
    
    return 0;
}
