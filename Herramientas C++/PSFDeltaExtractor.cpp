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

bool ReadEntireFile(const std::wstring& wPath, std::vector<BYTE>& outBuffer) {
    HANDLE hFile = CreateFileW(wPath.c_str(), GENERIC_READ, FILE_SHARE_READ, NULL, OPEN_EXISTING, FILE_ATTRIBUTE_NORMAL, NULL);
    if (hFile == INVALID_HANDLE_VALUE) return false;

    LARGE_INTEGER liSize;
    if (!GetFileSizeEx(hFile, &liSize) || liSize.QuadPart == 0) {
        CloseHandle(hFile);
        return false;
    }

    outBuffer.resize((size_t)liSize.QuadPart);
    DWORD bytesRead = 0;
    bool result = (ReadFile(hFile, outBuffer.data(), (DWORD)liSize.QuadPart, &bytesRead, NULL) && bytesRead == (DWORD)liSize.QuadPart);
    CloseHandle(hFile);
    return result;
}

int main(int argc, char* argv[]) {
    if (argc < 2) {
        std::cout << "PSFDeltaExtractor Native Reference-Aware Extractor v2.1" << std::endl;
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
    CreateDirectoryW(ToWString(dirName + "\\000").c_str(), NULL);

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

    std::cout << "PSFDeltaExtractor v2.1: Reference-aware extraction for " << psfFileName << "..." << std::endl;

    std::vector<BYTE> deltaReadBuffer;
    std::vector<BYTE> baseRefBuffer;
    deltaReadBuffer.reserve(10 * 1024 * 1024);

    std::string line;
    std::string currentFileName = "";
    std::string currentType = "RAW";
    ULONGLONG currentOffset = 0;
    ULONGLONG currentLength = 0;

    int processedCount = 0;

    while (std::getline(xmlFile, line)) {
        size_t namePos = line.find("name=\"");
        if (namePos != std::string::npos) {
            namePos += 6;
            size_t nameEnd = line.find("\"", namePos);
            if (nameEnd != std::string::npos) {
                currentFileName = line.substr(namePos, nameEnd - namePos);
            }
        }

        size_t typePos = line.find("type=\"");
        if (typePos != std::string::npos) {
            typePos += 6;
            size_t typeEnd = line.find("\"", typePos);
            if (typeEnd != std::string::npos) {
                currentType = line.substr(typePos, typeEnd - typePos);
            }
        }

        size_t offsetPos = line.find("offset=\"");
        if (offsetPos != std::string::npos) {
            offsetPos += 8;
            size_t offsetEnd = line.find("\"", offsetPos);
            if (offsetEnd != std::string::npos) {
                currentOffset = std::stoull(line.substr(offsetPos, offsetEnd - offsetPos));
            }
        }

        size_t lengthPos = line.find("length=\"");
        if (lengthPos != std::string::npos) {
            lengthPos += 8;
            size_t lengthEnd = line.find("\"", lengthPos);
            if (lengthEnd != std::string::npos) {
                currentLength = std::stoull(line.substr(lengthPos, lengthEnd - lengthPos));

                if (!currentFileName.empty() && currentLength > 0) {
                    std::string fullPathStr = dirName + "\\" + currentFileName;
                    std::wstring wFullPath = ToWString(fullPathStr);

                    if (GetFileAttributesW(wFullPath.c_str()) == INVALID_FILE_ATTRIBUTES) {
                        CreateDirectoriesForFile(wFullPath);

                        LARGE_INTEGER liOffset;
                        liOffset.QuadPart = currentOffset;
                        SetFilePointerEx(hPsf, liOffset, NULL, FILE_BEGIN);

                        if (deltaReadBuffer.size() < currentLength) {
                            deltaReadBuffer.resize((size_t)currentLength);
                        }

                        DWORD bytesRead = 0;
                        if (ReadFile(hPsf, deltaReadBuffer.data(), (DWORD)currentLength, &bytesRead, NULL) && bytesRead == currentLength) {
                            if (currentType == "RAW") {
                                HANDLE hOut = CreateFileW(wFullPath.c_str(), GENERIC_WRITE, 0, NULL, CREATE_ALWAYS, FILE_ATTRIBUTE_NORMAL, NULL);
                                if (hOut != INVALID_HANDLE_VALUE) {
                                    DWORD bytesWritten = 0;
                                    WriteFile(hOut, deltaReadBuffer.data(), (DWORD)currentLength, &bytesWritten, NULL);
                                    CloseHandle(hOut);
                                }
                            }
                            else {
                                std::wstring wRefPath1 = ToWString(dirName + "\\000\\" + currentFileName);
                                std::wstring wRefPath2 = wFullPath;
                                bool hasBaseRef = false;

                                if (GetFileAttributesW(wRefPath1.c_str()) != INVALID_FILE_ATTRIBUTES) {
                                    hasBaseRef = ReadEntireFile(wRefPath1, baseRefBuffer);
                                } else if (GetFileAttributesW(wRefPath2.c_str()) != INVALID_FILE_ATTRIBUTES) {
                                    hasBaseRef = ReadEntireFile(wRefPath2, baseRefBuffer);
                                }

                                DELTA_INPUT src = { 0 };
                                if (hasBaseRef && !baseRefBuffer.empty()) {
                                    src.lpStart = baseRefBuffer.data();
                                    src.uSize = baseRefBuffer.size();
                                    src.Editable = FALSE;
                                }

                                DELTA_INPUT dlt = { 0 };
                                dlt.lpStart = deltaReadBuffer.data();
                                dlt.uSize = (SIZE_T)currentLength;
                                dlt.Editable = TRUE;

                                DELTA_OUTPUT trg = { 0 };

                                if (ApplyDeltaB(0, src, dlt, &trg) && trg.lpStart != NULL) {
                                    HANDLE hOut = CreateFileW(wFullPath.c_str(), GENERIC_WRITE, 0, NULL, CREATE_ALWAYS, FILE_ATTRIBUTE_NORMAL, NULL);
                                    if (hOut != INVALID_HANDLE_VALUE) {
                                        DWORD bytesWritten = 0;
                                        WriteFile(hOut, trg.lpStart, (DWORD)trg.uSize, &bytesWritten, NULL);
                                        CloseHandle(hOut);
                                    }
                                    DeltaFree(trg.lpStart);
                                }
                            }
                        }
                    }

                    processedCount++;
                    currentFileName = "";
                    currentType = "RAW";
                    currentOffset = 0;
                    currentLength = 0;

                    if (processedCount % 500 == 0) {
                        SetProcessWorkingSetSize(GetCurrentProcess(), (SIZE_T)-1, (SIZE_T)-1);
                    }
                }
            }
        }
    }

    xmlFile.close();
    CloseHandle(hPsf);
    FreeLibrary(hDeltaModule);

    SetProcessWorkingSetSize(GetCurrentProcess(), (SIZE_T)-1, (SIZE_T)-1);
    std::cout << "PSFDeltaExtractor v2.1 finished: " << processedCount << " files extracted with exact reference matching." << std::endl;
    return 0;
}
