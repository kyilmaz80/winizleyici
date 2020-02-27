import sqlite3
from sqlite3 import Error
import json
from elasticsearch import Elasticsearch
from elasticsearch.helpers import bulk, streaming_bulk
from collections import OrderedDict
import uuid

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
    keys = ["processname", "windowtitle", "username",
            "createdate", "enddate", "durationmin"]
    for row_tupple in rows_list:
        #print("row_tupple: ", row_tupple)
        data_dict = {}
        for i in range(len(row_tupple)):
            data_dict[keys[i]] = row_tupple[i]
        data_rows.append(data_dict)
    if len(rows_list) > 1:
        data_rows.pop() # last row siliniyor...

    return data_rows

def dick_to_json(rows_dict):
    assert len(rows_dict) != 0
    try:
        json_data = json.dumps(rows_dict)
    except Exception as e:
        print(e)
        return None
    return json_data
"""
def get_bulk_dict(rows_list, index_name, doc_type):
    # source u olusturma
    source = ""
    actions = []
    for rows_dict in rows_list:
        for k, v in rows_dict.items():
            source += '"' + k + '":"' + str(v) + '",'
        action = {
            "_index": index_name,
            "_type": doc_type,
            "_source": "{" + source +
                        '"id":' +  str(uuid.uuid4()) + "}"
            }
        if action != "":
            actions.append(action)
    print("actions = ", actions)
    return actions
"""

def gen_data(data_rows):
    for data in data_rows:
        yield {
            "id": str(uuid.uuid4()),
            "_index": "test",
            "_type": "_doc",
            "_source": data,
        } 

def connect_to_elastic(host, port, username, password):
    es = Elasticsearch(host=host, port=port, http_auth=(username, password),)
    if es.ping():
        return es
    else:
        return None

def insert_to_elasticsearch(es, index_name, data_json, doc_type):
    #es  = connect_to_elastic(host, port, username, password)
    res = {}
    res["result"] = ""
    if es.ping():
        try:
            #TODO: mapper hatası mapper_parsing_exception
            print(data_json)
            res = es.index(index_name, body=data_json,
                           doc_type=doc_type)
        except Exception as e:
            print(e)
        return res["result"] == "created"
    else:
        return None

def add_bulk_es(es, data_json):
    print(data_json)
    res = bulk(es, data_json)
    return res

def main():
    database = r"C:\Users\Koray\Documents\AutoIT_win_capture\saruman_branch\worklog.db"

    #sqlite parameters
    MAX_RECORD_LEN = 10
    #elasticsearch parameters
    HOST = "elasticsearch.aryasoft.com.tr"
    USERNAME = "elasticsearch"
    PASSWORD = "SecureElast1c"
    PORT = "8080"
    INDEX_NAME = "test"
    DOCUMENT_TYPE = "_doc"
    
    # create a database connection
    conn = create_connection(database)
    data = {}

    with conn:
        #print("1. Query task by priority:")
        data = select_sqlitedata(conn, MAX_RECORD_LEN)

    #elasticsearch  connect & insert
    data_dict = rows_to_dict(data)
    data_json = dick_to_json(data_dict[0])
    data_json.replace("'", "\"")
    es  = connect_to_elastic(HOST, PORT, USERNAME, PASSWORD)
    #delete_elastic_index(es, INDEX_NAME)

    if es:
        """
        if insert_to_elasticsearch(es, INDEX_NAME, data_json, DOCUMENT_TYPE):
            print("data_dict[0] :", data_dict[0])
            print("data_dict[-1] :", data_dict[-1])
        """
        try:
            res = bulk(es, gen_data(data_dict))
        except Exception as e:
            print(e)

        print("result = ", res)
        
        
        #get_bulk_dict(data_dict, INDEX_NAME, DOCUMENT_TYPE)
        #if add_bulk_es(es, bulk_str):
        #    print("bulk eklendi dostum")
    else:
        print("Insert edilemedi!")
 
if __name__ == '__main__':
    main()
