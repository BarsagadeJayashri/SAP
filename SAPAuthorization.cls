public class SAPAuthorization implements Database.Batchable<sObject> ,Database.AllowsCallouts {
    private static final String SAP_API_ENDPOINT = 'https://sandbox.api.sap.com/sap/c4c/odata/v1/c4codataapi/LeadCollection?$inlinecount=allpages';
    private static final String SAP_API_KEY = 'AfkMw6ucUcH5fAY6TbjApKh8aT86TIiy';

    public  Iterable<sObject> start(Database.BatchableContext context) {
        return Database.getQueryLocator('SELECT Id FROM Lead');
        //return new List<sObject>();
    }

    public void execute(Database.BatchableContext context, List<sObject> scope) {
        List<Lead> leadsToInsert = new List<Lead>();

        HttpRequest req = new HttpRequest();
        req.setEndpoint(SAP_API_ENDPOINT);
        req.setMethod('GET');
        req.setHeader('APIKey', SAP_API_KEY);

        Http http = new Http();
        HttpResponse res = http.send(req);

        if (res.getStatusCode() == 200) {
            String responseBody = res.getBody();
            Dom.Document doc = new Dom.Document();
            doc.load(responseBody);

            String jsonResponse = convertXmlToJson(doc.getRootElement());
            processJsonResponse(jsonResponse, leadsToInsert);
        } else {
            String errorMessage = 'SAP API request failed with status code: ' + res.getStatusCode();
            System.debug(errorMessage);
        }

        if (!leadsToInsert.isEmpty()) {
            try {
                // Insert the leads
                upsert leadsToInsert Sap_Id__c;
                System.debug('Leads inserted successfully.');
            } catch (DmlException e) {
                // Handle the exception
                System.debug('An error occurred while inserting leads: ' + e.getMessage());
            }
        }
    }

    public void finish(Database.BatchableContext context) {
        // Perform any post-processing logic here
    }

    private String convertXmlToJson(Dom.XmlNode node) {
        Map<String, Object> jsonMap = new Map<String, Object>();
        buildJson(node, jsonMap);
        return JSON.serialize(jsonMap);
    }

    private void buildJson(Dom.XmlNode node, Map<String, Object> jsonMap) {
        if (node.getNodeType() == Dom.XmlNodeType.ELEMENT) {
            if (node.getChildElements().size() > 0) {
                List<Object> childList = new List<Object>();
                for (Dom.XmlNode childNode : node.getChildElements()) {
                    Map<String, Object> childMap = new Map<String, Object>();
                    buildJson(childNode, childMap);
                    childList.add(childMap);
                }
                jsonMap.put(node.getName(), childList);
            } else {
                jsonMap.put(node.getName(), node.getText());
            }
        }
    }

    private void processJsonResponse(String jsonResponse, List<Lead> leadsToInsert) {
        Map<String, Object> leadDataMap = (Map<String, Object>) JSON.deserializeUntyped(jsonResponse);

        List<Object> feedList = (List<Object>) leadDataMap.get('feed');
        List<Object> entryList;
        List<List<Object>> contentList = new List<List<Object>>();
        List<List<Object>> propertiesList = new List<List<Object>>();
        List<List<Object>> entries = new List<List<Object>>();

        for (Object feedObj : feedList) {
            Map<String, Object> feedMap = (Map<String, Object>) feedObj;
            entryList = (List<Object>) feedMap.get('entry');
            if (entryList != null)
                entries.add(entryList);
        }

        for (List<Object> entList : entries) {
            for (Object entryObj : entList) {
                Map<String, Object> entryMap = (Map<String, Object>) entryObj;
                List<Object> contentList1 = (List<Object>) entryMap.get('content');
                if (contentList1 != null)
                    contentList.add(contentList1);
            }
        }

        for (List<Object> conList : contentList) {
            for (Object contentObj : conList) {
                Map<String, Object> contentMap = (Map<String, Object>) contentObj;
                List<Object> propertyList1 = (List<Object>) contentMap.get('properties');
                if (propertyList1 != null) {
                    propertiesList.add(propertyList1);
                }
            }
        }

        for (List<Object> proList : propertiesList) {
            Map<String, Object> propertiesMap = new Map<String, Object>();
            for (Object propertiesObj : proList) {
                Map<String, Object> propertiesMap1 = (Map<String, Object>) propertiesObj;
                propertiesMap.putAll(propertiesMap1);
            }
            Lead objLead = new Lead();
            objLead.LastName = (String) propertiesMap.get('Name');
            objLead.Company = (String) propertiesMap.get('AccountPartyName');
            objLead.Sap_Id__c = (String) propertiesMap.get('ObjectID');
            leadsToInsert.add(objLead);
            propertiesMap.clear();
        }
    }
}