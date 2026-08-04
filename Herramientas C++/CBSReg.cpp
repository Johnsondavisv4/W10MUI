#define WIN32_LEAN_AND_MEAN
#include <windows.h>
#include <winsvc.h>
#include <tlhelp32.h>
#include <iostream>
#include <fstream>
#include <string>
#include <vector>
#include <sstream>

std::wstring ToWString(const std::string& str) {
    if (str.empty()) return L"";
    int size_needed = MultiByteToWideChar(CP_UTF8, 0, &str[0], (int)str.size(), NULL, 0);
    std::wstring wstrTo(size_needed, 0);
    MultiByteToWideChar(CP_UTF8, 0, &str[0], (int)str.size(), &wstrTo[0], size_needed);
    return wstrTo;
}

bool EnablePrivilege(HANDLE hToken, LPCWSTR lpszPrivilege) {
    TOKEN_PRIVILEGES tp;
    LUID luid;

    if (!LookupPrivilegeValueW(NULL, lpszPrivilege, &luid)) {
        return false;
    }

    tp.PrivilegeCount = 1;
    tp.Privileges[0].Luid = luid;
    tp.Privileges[0].Attributes = SE_PRIVILEGE_ENABLED;

    if (!AdjustTokenPrivileges(hToken, FALSE, &tp, sizeof(TOKEN_PRIVILEGES), NULL, NULL)) {
        return false;
    }

    return (GetLastError() != ERROR_NOT_ALL_ASSIGNED);
}

bool ImpersonateTrustedInstaller() {
    HANDLE hToken = NULL;
    if (!OpenProcessToken(GetCurrentProcess(), TOKEN_ADJUST_PRIVILEGES | TOKEN_QUERY, &hToken)) {
        return false;
    }

    EnablePrivilege(hToken, L"SeDebugPrivilege");
    EnablePrivilege(hToken, L"SeImpersonatePrivilege");
    CloseHandle(hToken);

    SC_HANDLE hSCM = OpenSCManagerW(NULL, NULL, SC_MANAGER_CONNECT);
    if (!hSCM) return false;

    SC_HANDLE hService = OpenServiceW(hSCM, L"TrustedInstaller", SERVICE_START | SERVICE_QUERY_STATUS);
    if (hService) {
        SERVICE_STATUS_PROCESS ssp;
        DWORD dwBytesNeeded;
        if (QueryServiceStatusEx(hService, SC_STATUS_PROCESS_INFO, (LPBYTE)&ssp, sizeof(ssp), &dwBytesNeeded)) {
            if (ssp.dwCurrentState == SERVICE_STOPPED) {
                StartServiceW(hService, 0, NULL);
                Sleep(500);
            }
        }
        CloseServiceHandle(hService);
    }
    CloseServiceHandle(hSCM);

    DWORD targetPID = 0;
    HANDLE hSnap = CreateToolhelp32Snapshot(TH32CS_SNAPPROCESS, 0);
    if (hSnap != INVALID_HANDLE_VALUE) {
        PROCESSENTRY32W pe;
        pe.dwSize = sizeof(pe);
        if (Process32FirstW(hSnap, &pe)) {
            do {
                if (_wcsicmp(pe.szExeFile, L"TrustedInstaller.exe") == 0) {
                    targetPID = pe.th32ProcessID;
                    break;
                }
            } while (Process32NextW(hSnap, &pe));
        }
        CloseHandle(hSnap);
    }

    if (targetPID == 0) return false;

    HANDLE hProc = OpenProcess(PROCESS_QUERY_INFORMATION, FALSE, targetPID);
    if (!hProc) return false;

    HANDLE hProcToken = NULL;
    if (!OpenProcessToken(hProc, TOKEN_DUPLICATE | TOKEN_QUERY, &hProcToken)) {
        CloseHandle(hProc);
        return false;
    }

    HANDLE hDupToken = NULL;
    if (DuplicateTokenEx(hProcToken, MAXIMUM_ALLOWED, NULL, SecurityImpersonation, TokenImpersonation, &hDupToken)) {
        SetThreadToken(NULL, hDupToken);
        CloseHandle(hDupToken);
    }

    CloseHandle(hProcToken);
    CloseHandle(hProc);
    return true;
}

void ProcessRegistryLine(const std::string& line) {
    if (line.empty()) return;

    if (line.find("New-ItemProperty") != std::string::npos) {
        size_t keyStart = line.find("'HKLM:\\");
        if (keyStart == std::string::npos) keyStart = line.find("\"HKLM:\\");
        if (keyStart == std::string::npos) return;

        char quoteChar = line[keyStart];
        keyStart += 7;
        size_t keyEnd = line.find(quoteChar, keyStart);
        if (keyEnd == std::string::npos) return;

        std::string subKeyStr = line.substr(keyStart, keyEnd - keyStart);

        std::string rest = line.substr(keyEnd + 1);
        std::stringstream ss(rest);
        std::string valueName;
        ss >> valueName;

        size_t valPos = line.find("-Value ");
        DWORD dwValue = 0;
        if (valPos != std::string::npos) {
            std::string valStr = line.substr(valPos + 7);
            std::stringstream valSS(valStr);
            valSS >> dwValue;
        }

        std::wstring wSubKey = ToWString(subKeyStr);
        std::wstring wValueName = ToWString(valueName);

        HKEY hKey = NULL;
        DWORD dwDisposition = 0;
        if (RegCreateKeyExW(HKEY_LOCAL_MACHINE, wSubKey.c_str(), 0, NULL, REG_OPTION_NON_VOLATILE, KEY_ALL_ACCESS, NULL, &hKey, &dwDisposition) == ERROR_SUCCESS) {
            RegSetValueExW(hKey, wValueName.c_str(), 0, REG_DWORD, (const BYTE*)&dwValue, sizeof(DWORD));
            RegCloseKey(hKey);
        }
    }
    else if (line.find("Remove-ItemProperty") != std::string::npos) {
        size_t keyStart = line.find("'HKLM:\\");
        if (keyStart == std::string::npos) keyStart = line.find("\"HKLM:\\");
        if (keyStart == std::string::npos) return;

        char quoteChar = line[keyStart];
        keyStart += 7;
        size_t keyEnd = line.find(quoteChar, keyStart);
        if (keyEnd == std::string::npos) return;

        std::string subKeyStr = line.substr(keyStart, keyEnd - keyStart);

        size_t valStart = line.find(quoteChar, keyEnd + 1);
        if (valStart == std::string::npos) return;
        size_t valEnd = line.find(quoteChar, valStart + 1);
        if (valEnd == std::string::npos) return;

        std::string valueNameStr = line.substr(valStart + 1, valEnd - valStart - 1);

        std::wstring wSubKey = ToWString(subKeyStr);
        std::wstring wValueName = ToWString(valueNameStr);

        HKEY hKey = NULL;
        if (RegOpenKeyExW(HKEY_LOCAL_MACHINE, wSubKey.c_str(), 0, KEY_ALL_ACCESS, &hKey) == ERROR_SUCCESS) {
            RegDeleteValueW(hKey, wValueName.c_str());
            RegCloseKey(hKey);
        }
    }
}

int main(int argc, char* argv[]) {
    if (argc < 2) {
        std::cout << "CBSReg Native Registry Modifier v1.0" << std::endl;
        std::cout << "Usage: CBSReg.exe <path_to_W10UIreg.txt>" << std::endl;
        return 1;
    }

    std::string regFilePath = argv[1];
    std::ifstream inFile(regFilePath);
    if (!inFile.is_open()) {
        std::cerr << "Failed to open registry command file: " << regFilePath << std::endl;
        return 1;
    }

    ImpersonateTrustedInstaller();

    std::string line;
    while (std::getline(inFile, line)) {
        ProcessRegistryLine(line);
    }

    inFile.close();
    return 0;
}
