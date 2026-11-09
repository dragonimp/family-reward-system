using LinkoFamily;
static void Check(bool value,string label){if(!value)throw new Exception(label);Console.WriteLine("PASS "+label);}
var start=DateTimeOffset.Parse("2026-11-09T04:00:00Z");var a=Guid.NewGuid();var b=Guid.NewGuid();
ExerciseRouteCoordinate Point(int seconds,Guid? segment=null,double latitude=31)=>new(latitude,121,start.AddSeconds(seconds),segment??a);
Check(ExerciseRouteGeometry.Segments([]).Count==0,"empty history does not fabricate a route");
var continuous=ExerciseRouteGeometry.Segments([Point(0),Point(5),Point(10)]);
Check(continuous.Count==1&&continuous[0].Count==3&&continuous[0][0][0]==31&&continuous[0][0][1]==121,"continuous GPS points retain latitude-longitude order");
Check(ExerciseRouteGeometry.Segments([Point(0),Point(5),Point(10,b)]).Count==2,"paused and resumed segments are not joined");
Check(ExerciseRouteGeometry.Segments([Point(0),Point(65)]).Count==2,"stale GPS gaps do not fabricate traversed paths");
Check(ExerciseRouteGeometry.Segments([Point(0),Point(5,latitude:double.NaN),Point(10)]).Count==2,"invalid coordinates split geometry and never reach the renderer");
Check(ExerciseRouteGeometry.Segments([Point(5),Point(4)]).Count==2,"reversed timestamps cannot join route segments");
Check(ExerciseRouteGeometry.Segments([Point(0),Point(60)]).Count==1,"one minute boundary stays connected");
