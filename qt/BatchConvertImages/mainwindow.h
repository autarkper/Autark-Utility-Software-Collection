#ifndef MAINWINDOW_H
#define MAINWINDOW_H

#include <QMainWindow>

namespace Ui {
    class MainWindow;
}

class QAbstractButton;

class MainWindow : public QMainWindow {
    Q_OBJECT
public:
    MainWindow(QWidget *parent = 0);
    ~MainWindow();

protected:
    void changeEvent(QEvent *e);

private:
    Ui::MainWindow *ui;
    QStringList m_fileNames;
    bool m_usingBrowseInput;
    QString m_find_dir;
    QString m_find_pattern;
    QString m_userPpi;
    bool m_changingPreset;
    void on_bnOK_pressed__(bool isDryRun);

private slots:
    void on_bnDryRun_pressed();
    void on_lePPI_textChanged(QString );
    void on_lnInputDir_textChanged(QString );
    void on_leWidth_textEdited(QString );
    void on_leHeight_textChanged(QString );
    void on_cbUnits_currentIndexChanged(QString );
    void on_nClearInput_clicked();
    void on_bnClearOutput_clicked();
    void on_chkNoSuffix_clicked();
    void on_chkStraight_clicked();
    void on_lnInputDir_editingFinished();
    void on_bn_browseInputProfile_pressed();
    void on_bn_browseProfile_clicked();
    void on_lePPI_textEdited(QString );
    void on_buttonBox_clicked(QAbstractButton* button);
    void on_cbDimPresets_currentIndexChanged(int index);
    void on_bnOK_pressed();
    void on_bnOutputBrowse_clicked();
    void on_bnInputBrowse_clicked();
};

#endif // MAINWINDOW_H
