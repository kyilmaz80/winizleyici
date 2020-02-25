import sqlite3
from sqlite3 import Error
import json
from elasticsearch import Elasticsearch
from collections import OrderedDict

def create_connection(db_file):
    """ create a database connection to the SQLite database
    specified by the db_file
    :param db_file: database file
    :return: Connection object or None
    """
    conn = None
    try:
        conn = sqlite3.connect(db_file)
    except Error as e:
        print(e)
 
    return conn

def delete_elastic_index(es, index_name):
    res = es.indices.delete(index_name)
    return res["acknowledged"]
 
def select_all_rows(conn):
    """
    Query all rows in the tasks table
    :param conn: the Connection object
    :return:
    """
    cur = conn.cursor()
    cur.execute("SELECT * FROM vw_workdata")
 
    rows = cur.fetchall()
 
    for row in rows:
        print(row)
 
 
def select_sqlitedata(conn, priority):
    """
    Query tasks by priority
    :param conn: the Connection object
    :param priority:
    :return:
    """
    cur = conn.cursor()
    
    cur.execute("SELECT * FROM vw_workdata LIMIT ?", (priority,))
 
    rows = cur.fetchall()

    return rows
 
def rows_to_dict(rows_list):
    data_rows = []
    assert len(rows_list) != 0
    # rows bir liste
    # icinde de tupple var
    keys = ["id", "process", "title", "username", "start_date", "end_date", "duration"]
    for row_tupple in rows_list:
        #print("row_tupple: ", row_tupple)
        data_dict = {}
        for i in range(len(row_tupple)):
            data_dict[keys[i]] = row_tupple[i]
        data_rows.append(data_dict)

    return data_rows

def dick_to_json(rows_dict):
    assert len(rows_dict) != 0
    try:
        json_data = json.dumps(rows_dict)
    except Exception as e:
        print(e)
        return None
    return json_data

def connect_to_elastic(host, port, username, password):
    es = Elasticsearch(host=host, port=port, http_auth=(username, password),)
    if es.ping():
        return es
    else:
        return None

def insert_to_elasticsearch(es, index_name, data_json):
    #es  = connect_to_elastic(host, port, username, password)
    res = {}
    res["result"] = ""
    if es.ping():
        try:
            #TODO: mapper hatası mapper_parsing_exception
            res = es.index(index_name, body=data_json)
        except Exception as e:
            print(e)
        return res["result"] == "created"
    else:
        return None
    
def main():
    database = r"C:\Users\Koray\Documents\AutoIT_win_capture\saruman_branch\worklog.db"

    #sqlite parameters
    MAX_RECORD_LEN = 2
    #elasticsearch parameters
    HOST = "elasticsearch.aryasoft.com.tr"
    USERNAME = "elasticsearch"
    PASSWORD = "SecureElast1c"
    PORT = "8080"
    INDEX_NAME = "test"
    
    # create a database connection
    conn = create_connection(database)
    data = {}

    with conn:
        #print("1. Query task by priority:")
        data = select_sqlitedata(conn, MAX_RECORD_LEN)

    #elasticsearch  connect & insert
    data_dict = rows_to_dict(data)
    data_json = dick_to_json(data_dict)
    es  = connect_to_elastic(HOST, PORT, USERNAME, PASSWORD)
    delete_elastic_index(es, INDEX_NAME)

    if es:
        if insert_to_elasticsearch(es, INDEX_NAME, data_json):
            print("data_dict[0] :", data_dict[0])
            print("data_dict[-1] :", data_dict[-1])
    else:
        print("Insert edilemedi!")
    
    """
    data_dict = rows_to_dict(data)
    data_json = dick_to_json(data_dict)
    #print("JSON:")
    #print(data_json)
    print("......")
    print("data_dict[0] :", data_dict[0])
    print(type(data_dict), len(data_dict))
    print("....")
    print("data_dict[-1] : ", data_dict[-1])
    """
 
 
if __name__ == '__main__':
    main()
