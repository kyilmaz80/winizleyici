SET PYTHON38=C:\Users\%username%\AppData\Local\Programs\Python\Python38

%PYTHON38%\scripts\pyinstaller.exe sync_sqlite2es.py --onefile --clean

rmdir /S build
rmdir /S __pycache__
del sync_sqlite2es.spec

