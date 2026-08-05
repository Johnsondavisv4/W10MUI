#define WIN32_LEAN_AND_MEAN
#include <windows.h>
#include <iostream>
#include <fstream>
#include <string>
#include <vector>
#include <sstream>

typedef struct _DELTA_INPUT {
    union {
        LPCVOID lpStart;
        LPCSTR  lpszStart;
    };
    SIZE_T uSize;
    BOOL   Editable;
} DELTA_INPUT, *PDELTA_INPUT;

typedef struct _DELTA_OUTPUT {
    LPVOID lpStart;
    SIZE_T uSize;
} DELTA_OUTPUT, *PDELTA_OUTPUT;

typedef BOOL (WINAPI *pfnApplyDeltaB)(
    ULONG64 ApplyFlags,
    DELTA_INPUT Source,
    DELTA_INPUT Delta,
    PDELTA_OUTPUT Target
);

typedef BOOL (WINAPI *pfnDeltaFree)(
    LPVOID lpStart
);

std::wstring ToWString(const std::string& str) {
    if (str.empty()) return L"";
    int size_needed = MultiByteToWideChar(CP_UTF8, 0, &str[0], (int)str.size(), NULL, 0);
    std::wstring wstrTo(size_needed, 0);
    MultiByteToWideChar(CP_UTF8, 0, &str[0], (int)str.size(), &wstrTo[0], size_needed);
    return wstrTo;
}

void CreateDirectoriesForFile(const std::wstring& filePath) {
    size_t pos = 0;
    while ((pos = filePath.find_first_of(L"\\/", pos + 1)) != std::wstring::npos) {
        std::wstring dir = filePath.substr(0, pos);
        if (!dir.empty() && dir.back() != L':') {
            CreateDirectoryW(dir.c_str(), NULL);
        }
    }
}

std::string ExtractAttribute(const std::string& block, const std::string& attrName) {
    size_t pos = block.find(attrName);
    if (pos == std::string::npos) return "";
    pos += attrName.length();
    size_t endPos = block.find("\"", pos);
    if (endPos == std::string::npos) return "";
    return block.substr(pos, endPos - pos);
}

int main(int argc, char* argv[]) {
    if (argc < 2) {
        std::cout << "PSFDeltaExtractor Native Deterministic Engine v4.0" << std::endl;
        std::cout << "Usage: PSFDeltaExtractor.exe <cab_package_name> [dll_path]" << std::endl;
        return 1;
    }

    std::string cabFile = argv[1];
    std::string dllName = (argc >= 3) ? argv[2] : "msdelta.dll";

    wchar_t sysDir[MAX_PATH];
    GetSystemDirectoryW(sysDir, MAX_PATH);
    std::wstring ucPath = std::wstring(sysDir) + L"\\UpdateCompression.dll";
    if (GetFileAttributesW(ucPath.c_str()) != INVALID_FILE_ATTRIBUTES && dllName == "msdelta.dll") {
        dllName = "UpdateCompression.dll";
    }

    HMODULE hDeltaModule = LoadLibraryW(ToWString(dllName).c_str());
    if (!hDeltaModule) {
        hDeltaModule = LoadLibraryW(L"msdelta.dll");
    }

    if (!hDeltaModule) {
        std::cerr << "Error: Could not load " << dllName << std::endl;
        return 1;
    }

    pfnApplyDeltaB ApplyDeltaB = (pfnApplyDeltaB)GetProcAddress(hDeltaModule, "ApplyDeltaB");
    pfnDeltaFree DeltaFree = (pfnDeltaFree)GetProcAddress(hDeltaModule, "DeltaFree");

    if (!ApplyDeltaB || !DeltaFree) {
        std::cerr << "Error: Could not locate ApplyDeltaB/DeltaFree" << std::endl;
        FreeLibrary(hDeltaModule);
        return 1;
    }

    std::string dirName = cabFile;
    size_t lastDot = dirName.find_last_of('.');
    if (lastDot != std::string::npos) {
        dirName = dirName.substr(0, lastDot);
    }

    std::string psfFileName = dirName + ".psf";
    std::string xmlPath = dirName + "\\express.psf.cix.xml";

    CreateDirectoryW(ToWString(dirName).c_str(), NULL);

    HANDLE hPsf = CreateFileW(ToWString(psfFileName).c_str(), GENERIC_READ, FILE_SHARE_READ, NULL, OPEN_EXISTING, FILE_ATTRIBUTE_NORMAL, NULL);
    if (hPsf == INVALID_HANDLE_VALUE) {
        std::cerr << "Error: Could not open PSF file " << psfFileName << std::endl;
        FreeLibrary(hDeltaModule);
        return 1;
    }

    std::ifstream xmlFile(xmlPath);
    if (!xmlFile.is_open()) {
        std::cerr << "Error: Could not open XML file " << xmlPath << std::endl;
        CloseHandle(hPsf);
        FreeLibrary(hDeltaModule);
        return 1;
    }

    std::string xmlContent((std::istreambuf_iterator<char>(xmlFile)), std::istreambuf_iterator<char>());
    xmlFile.close();

    std::cout << "PSFDeltaExtractor v4.0: Deterministic 1:1 extraction engine for " << psfFileName << "..." << std::endl;

    std::vector<BYTE> buffer;
    buffer.reserve(10 * 1024 * 1024);

    int processedCount = 0;
    size_t pos = 0;

    while ((pos = xmlContent.find("<File ", pos)) != std::string::npos) {
        size_t endPos = xmlContent.find("</File>", pos);
        if (endPos == std::string::npos) endPos = xmlContent.find("/>", pos);
        if (endPos == std::string::npos) break;

        std::string fileBlock = xmlContent.substr(pos, endPos - pos + 7);
        pos = endPos + 2;

        std::string fileName = ExtractAttribute(fileBlock, "name=\"");
        std::string timeStr = ExtractAttribute(fileBlock, "time=\"");

        size_t srcPos = fileBlock.find("<Source ");
        if (srcPos == std::string::npos) continue;

        std::string srcBlock = fileBlock.substr(srcPos);
        std::string stype = ExtractAttribute(srcBlock, "type=\"");
        std::string offsetStr = ExtractAttribute(srcBlock, "offset=\"");
        std::string lengthStr = ExtractAttribute(srcBlock, "length=\"");

        if (fileName.empty() || offsetStr.empty() || lengthStr.empty()) continue;

        ULONGLONG offset = std::stoull(offsetStr);
        ULONGLONG length = std::stoull(lengthStr);

        std::string fullPathStr = dirName + "\\" + fileName;
        std::wstring wFullPath = ToWString(fullPathStr);

        if (GetFileAttributesW(wFullPath.c_str()) == INVALID_FILE_ATTRIBUTES) {
            CreateDirectoriesForFile(wFullPath);

            LARGE_INTEGER liOffset;
            liOffset.QuadPart = offset;
            SetFilePointerEx(hPsf, liOffset, NULL, FILE_BEGIN);

            if (buffer.size() < length) {
                buffer.resize((size_t)length);
            }

            DWORD bytesRead = 0;
            if (ReadFile(hPsf, buffer.data(), (DWORD)length, &bytesRead, NULL) && bytesRead == length) {
                HANDLE hOut = CreateFileW(wFullPath.c_str(), GENERIC_READ | GENERIC_WRITE, 0, NULL, CREATE_ALWAYS, FILE_ATTRIBUTE_NORMAL, NULL);
                if (hOut != INVALID_HANDLE_VALUE) {
                    DWORD bytesWritten = 0;
                    WriteFile(hOut, buffer.data(), (DWORD)length, &bytesWritten, NULL);

                    if (stype == "PA30" || stype == "PA31") {
                        DELTA_INPUT src = { 0 };
                        DELTA_INPUT dlt = { 0 };
                        DELTA_OUTPUT trg = { 0 };

                        dlt.lpStart = buffer.data();
                        dlt.uSize = (SIZE_T)length;
                        dlt.Editable = TRUE;

                        if (ApplyDeltaB(0, src, dlt, &trg) && trg.lpStart != NULL) {
                            SetFilePointer(hOut, 0, NULL, FILE_BEGIN);
                            SetEndOfFile(hOut);
                            WriteFile(hOut, trg.lpStart, (DWORD)trg.uSize, &bytesWritten, NULL);
                            DeltaFree(trg.lpStart);
                        }
                    }

                    if (!timeStr.empty()) {
                        try {
                            ULONGLONG ftVal = std::stoull(timeStr);
                            FILETIME ft;
                            ft.dwLowDateTime = (DWORD)(ftVal & 0xFFFFFFFF);
                            ft.dwHighDateTime = (DWORD)(ftVal >> 32);
                            SetFileTime(hOut, NULL, NULL, &ft);
                        } catch (...) {}
                    }

                    CloseHandle(hOut);
                }
            }
        }

        processedCount++;
        if (processedCount % 1000 == 0) {
            SetProcessWorkingSetSize(GetCurrentProcess(), (SIZE_T)-1, (SIZE_T)-1);
        }
    }

    CloseHandle(hPsf);
    FreeLibrary(hDeltaModule);

    SetProcessWorkingSetSize(GetCurrentProcess(), (SIZE_T)-1, (SIZE_T)-1);
    std::cout << "PSFDeltaExtractor v4.0 finished: " << processedCount << " files extracted deterministically." << std::endl;
    return 0;
}
