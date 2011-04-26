#ifndef PROCESSOUTPUTDLG_H
#define PROCESSOUTPUTDLG_H

#include <QDialog>
#include <QProcess>

namespace Ui {
    class ProcessOutputDlg;
}

class ProcessOutputDlg : public QDialog {
    Q_OBJECT
public:
    ProcessOutputDlg(QString const & program, QStringList const & args, QWidget *parent = 0);
    ~ProcessOutputDlg();

protected:
    void changeEvent(QEvent *e);

private:
    Ui::ProcessOutputDlg *ui;
    QProcess m_process;
    int m_noCloseCounter; // prevent close if non-zero
    bool m_aborting;
    int m_exitCode;

    void reject();
private slots:
    void on_bnClose_clicked();
    void readData();
    void on_process_finished ( int exitCode, QProcess::ExitStatus exitStatus );
    void on_process_error( QProcess::ProcessError error );
};

#endif // PROCESSOUTPUTDLG_H
