cmake_minimum_required(VERSION 3.21)
project(xjaus_kde VERSION 1.2.4 LANGUAGES CXX)

set(CMAKE_CXX_STANDARD 20)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_AUTOMOC ON)

find_package(Qt6 6.5 REQUIRED COMPONENTS Core Gui Qml Quick QuickControls2 WebChannel WebEngineQuick)
find_package(KF6Kirigami REQUIRED)

set(XJAUS_BACKEND_PATH "" CACHE FILEPATH "Prebuilt xjaus_backend executable to include in a Linux package")
set(XJAUS_WEB_ROOT "${CMAKE_CURRENT_SOURCE_DIR}/../dist" CACHE PATH "Built XJAUS web renderer used for WebRTC playback")

qt_standard_project_setup(REQUIRES 6.5)

qt_add_executable(xjaus-kde
    main.cpp
    sidecarclient.cpp
    sidecarclient.h
)

qt_add_qml_module(xjaus-kde
    URI XjausKde
    VERSION 1.0
    QML_FILES
        Main.qml
)

qt_add_resources(xjaus-kde "xjaus_webchannel_bridge"
    PREFIX "/xjaus"
    FILES webchannel-bridge.js
)

target_link_libraries(xjaus-kde PRIVATE
    Qt6::Core
    Qt6::Gui
    Qt6::Qml
    Qt6::Quick
    Qt6::QuickControls2
    Qt6::WebChannel
    Qt6::WebEngineQuick
    KF6::Kirigami
)
target_compile_definitions(xjaus-kde PRIVATE XJAUS_KDE_VERSION="${PROJECT_VERSION}")

install(TARGETS xjaus-kde RUNTIME DESTINATION bin)

install(FILES
    "${CMAKE_CURRENT_SOURCE_DIR}/io.github.xjaus.xjaus.desktop"
    DESTINATION share/applications
)
if(EXISTS "${XJAUS_WEB_ROOT}/index.html")
    install(DIRECTORY "${XJAUS_WEB_ROOT}/" DESTINATION share/xjaus/web)
else()
    message(STATUS "No built renderer found; KDE shell will launch without the playback page")
endif()
install(FILES
    "${CMAKE_CURRENT_SOURCE_DIR}/../assets/icon.png"
    DESTINATION share/icons/hicolor/512x512/apps
    RENAME io.github.xjaus.xjaus.png
)

if(XJAUS_BACKEND_PATH)
    if(NOT EXISTS "${XJAUS_BACKEND_PATH}" OR IS_DIRECTORY "${XJAUS_BACKEND_PATH}")
        message(FATAL_ERROR "XJAUS_BACKEND_PATH must point to the built xjaus_backend executable")
    endif()
    install(PROGRAMS "${XJAUS_BACKEND_PATH}" DESTINATION lib/xjaus RENAME xjaus_backend)
endif()

set(CPACK_PACKAGE_NAME "xjaus-kde")
set(CPACK_PACKAGE_VENDOR "XJAUS contributors")
set(CPACK_PACKAGE_CONTACT "XJAUS contributors")
set(CPACK_PACKAGE_DESCRIPTION_SUMMARY "Native KDE frontend for Xbox Cloud Gaming and Remote Play")
set(CPACK_PACKAGE_VERSION "${PROJECT_VERSION}")
set(CPACK_RPM_PACKAGE_RELEASE "3")
set(CPACK_PACKAGING_INSTALL_PREFIX "/usr")
set(CPACK_GENERATOR "RPM")
set(CPACK_RPM_PACKAGE_LICENSE "GPL-3.0-only")
set(CPACK_RPM_PACKAGE_GROUP "Amusements/Games")
set(CPACK_RPM_PACKAGE_REQUIRES "kf6-kirigami, qt6-qtbase, qt6-qtdeclarative, qt6-qtquickcontrols2, qt6-qtwebchannel, qt6-qtwebengine, libsecret, webkit2gtk4.1")
include(CPack)
