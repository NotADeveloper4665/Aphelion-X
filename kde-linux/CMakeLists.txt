cmake_minimum_required(VERSION 3.21)
project(xjaus_kde VERSION 1.2.4 LANGUAGES CXX)

set(CMAKE_CXX_STANDARD 20)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_AUTOMOC ON)

find_package(Qt6 6.5 REQUIRED COMPONENTS Core Gui Qml Quick QuickControls2)
find_package(KF6Kirigami REQUIRED)

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

target_link_libraries(xjaus-kde PRIVATE
    Qt6::Core
    Qt6::Gui
    Qt6::Qml
    Qt6::Quick
    Qt6::QuickControls2
    KF6::Kirigami
)

install(TARGETS xjaus-kde RUNTIME DESTINATION bin)
