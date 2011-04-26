# -------------------------------------------------
# Project created by QtCreator 2009-12-03T16:06:00
# -------------------------------------------------
TARGET = BatchConvertImages
TEMPLATE = app
SOURCES += main.cpp \
    mainwindow.cpp \
    processoutputdlg.cpp
HEADERS += mainwindow.h \
    processoutputdlg.h
FORMS += mainwindow.ui \
    processoutputdlg.ui
LIBS += -lboost_filesystem-mt \
    -lboost_regex-mt
