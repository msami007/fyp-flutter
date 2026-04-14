import 'package:flutter/material.dart';

void main() {
  runApp(squareApp());
}

class squareApp extends StatelessWidget{
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Flutter Square Calc',
      home: SquareHome(),
    );
  }
}
class SquareHome extends StatefulWidget{
  _SquareHomeState createState() => _SquareHomeState();
}

class _SquareHomeState extends State<SquareHome>{
  TextEditingController txtNum = TextEditingController();
  String result = '';
  void calculateSquare(){
    final number = double.tryParse(txtNum.text);
    if(number != null) {
      final square = number * number;
      setState(() {
        result = 'The square of $number is $square';
      });
    }
    else{
      setState(() {
        result = 'Invalid input. Please enter a valid number.';
      });
    }
  }
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Square Calculator')),
        body: Padding(
          padding: const EdgeInsets.all(20), // symmetric(horizontal: 20, vertical: 20) fromLTRB(20, 20, 20, 20) only
          child: Column(
            mainAxisAlignment: MainAxisAlignment.start,
            children: [TextField(
              controller: txtNum,
              decoration: InputDecoration(
                border: OutlineInputBorder(),
                labelText: 'Enter a number',
              ),
              keyboardType: TextInputType.number,
            ),
            SizedBox(height: 20),
            ElevatedButton(
              onPressed: calculateSquare,
              child: Text('Calculate Me'),
              ),
            SizedBox(height: 20),
            Text(
              result,
              style: TextStyle(fontSize: 18),
            )  ]
          )
        ),
    );
  }

}